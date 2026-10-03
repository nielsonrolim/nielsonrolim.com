require "open3"
require "timeout"
require "tmpdir"
require "json"

# Thin wrapper around the `yt-dlp` CLI, used only as a *fallback* transcript
# source for YouTube videos.
#
# YouTube's caption endpoint (`api/timedtext`) now often answers HTTP 200 with an
# empty body because it requires a PoToken (`exp=xpe` in the track's baseUrl).
# The watch page still lists the tracks, so the primary path in `YoutubeFetcher`
# sees "there are captions" but gets no text. `yt-dlp` gets the real captions
# through the `android_vr` player client without a PoToken provider, Node/Deno or
# a proxy, so it is the second attempt when the page's own tracks yield nothing.
#
# Unlike every feed/article fetch, this service does **not** go through
# `HttpTransport`, so it has **no SSRF guard**: it spawns a binary that contacts
# a fixed host (`www.youtube.com`). That is why it only ever accepts a video id
# already reconstructed and validated by format (\A[A-Za-z0-9_-]{11}\z), never a
# URL from third-party content. `YoutubeFetcher` is the only caller and it
# derives the id itself from the watch URL (see its `video_id`). Do not add a
# URL-shaped input here.
class YtdlpCli
  # YouTube ids are exactly 11 URL-safe characters. Anything else never reaches
  # the command line.
  VIDEO_ID = /\A[A-Za-z0-9_-]{11}\z/

  # The language code sanitizer must match YoutubeFetcher's own (see the
  # `Accept-Language` guard in transcript_for): a malformed value from the page
  # must never reach the argument array or become a yt-dlp option.
  LANGUAGE_CODE = /\A[\w-]+\z/

  # Cap on the language list, so a page listing hundreds of tracks cannot build
  # an unbounded `--sub-langs` argument (and a burst of downloads).
  MAX_LANGUAGES = 8

  # The player client that still serves captions without a PoToken provider.
  # Overridable for a future YouTube change without a deploy.
  DEFAULT_PLAYER_CLIENT = "android_vr"

  # The subtitle file yt-dlp writes, named `sub.<lang>.json3` by `-o sub`.
  # The glob is deliberately `sub.*.json3`: `sub*.json3` would also match a bare
  # `sub.json3`, which carries no language tag to rank by.
  SUBTITLE_GLOB = "sub.*.json3"
  SUBTITLE_SUFFIX = /\.json3\z/

  # Long enough for a normal fetch of a large caption track; the socket timeout
  # below bounds the network wait separately.
  DEFAULT_TIMEOUT = 60

  # A 429 from YouTube is an IP rate limit, not a permanent failure, so one
  # short backoff often gets the track on the second try.
  RETRY_WAIT = 3

  class TimeoutError < StandardError; end

  # The status object the runner returns. The real runner and the test fake both
  # produce something shaped like this, so `call` only depends on `success?`.
  # `stderr` carries the run's stderr (empty on the fake unless a scenario sets
  # it); it is only used to recognise a transient rate limit.
  Status = Struct.new(:success, :exitstatus, :stderr) do
    def initialize(success, exitstatus, stderr = "")
      super(success, exitstatus, stderr.to_s)
    end

    def success?
      success
    end
  end

  # Set once so a missing binary logs a single line instead of one per video.
  @missing_binary_logged = false

  class << self
    attr_accessor :missing_binary_logged

    # Runs yt-dlp and returns a Status. `args` is the argument array (never a
    # shell string), `chdir` is the directory yt-dlp writes the subtitle file
    # into. Raises TimeoutError if the run overruns.
    #
    # This class method *is* the injectable seam: `YtdlpCli.new(runner:)` takes
    # any object responding to `call(args, chdir:)` and returning a Status. The
    # fake uses it to inspect the built args and to write the scenario's
    # `.json3` files into `chdir`.
    def self.exec(args, chdir:, timeout: DEFAULT_TIMEOUT)
      # pgroup so a timeout can take down yt-dlp *and* anything it spawned.
      Open3.popen3("yt-dlp", *args, chdir: chdir, pgroup: true) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        # Read both pipes concurrently: reading them in sequence would deadlock
        # once either filled its OS pipe buffer.
        readers = [ Thread.new { stdout.read }, Thread.new { stderr.read } ]
        begin
          ::Timeout.timeout(timeout) do
            # Drain both pipes concurrently: reading them in sequence would
            # deadlock once either filled its OS pipe buffer. Only stderr is
            # kept (for the rate-limit retry); yt-dlp writes the subtitle file.
            _stdout, stderr_out = readers.map(&:value)
            process_status = wait_thr.value
            return Status.new(process_status.success?, process_status.exitstatus, stderr_out)
          end
        rescue ::Timeout::Error
          readers.each { |reader| reader.kill }
          kill_process_group(wait_thr.pid)
          raise TimeoutError, "yt-dlp did not finish within #{timeout}s"
        end
      end
    end

    # Takes down yt-dlp and anything it spawned. The direct child is left for
    # popen3's own ensure to reap; killing the group handles grandchildren, which
    # are reparented once their parent dies.
    def self.kill_process_group(pid)
      Process.kill("TERM", -pid)
      sleep 0.5
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
    private_class_method :kill_process_group

    def player_client
      ENV.fetch("YTDLP_PLAYER_CLIENT", DEFAULT_PLAYER_CLIENT)
    end
  end

  # `runner` defaults to nil, meaning the real `Open3` runner above. Tests inject
  # a fake so no process is ever spawned.
  def initialize(runner: nil, timeout: DEFAULT_TIMEOUT)
    @runner = runner
    @timeout = timeout
  end

  attr_reader :runner, :timeout

  # `video_id` is a validated YouTube id, `languages` a list of language tags in
  # order of preference. Returns the normalized transcript text, or nil when
  # there is none. Never raises for a subprocess failure, timeout or missing
  # binary; a timeout raised by the runner is rescued here.
  def call(video_id:, languages: [])
    id = video_id.to_s
    return nil unless id.match?(VIDEO_ID)

    langs = sanitize_languages(languages)

    with_retry(id, langs)
  rescue TimeoutError
    Rails.logger.warn("yt-dlp timed out for #{video_id}")
    nil
  rescue Errno::ENOENT
    log_missing_binary
    nil
  end

  private

  # One attempt, then a second only when the failure named a rate limit (any
  # other non-zero exit is permanent within this call). Returns the transcript or
  # nil; the temp directory is cleaned up by the block either way.
  def with_retry(id, langs)
    result = attempt(id, langs)
    return result if result.present? || !rate_limited?

    sleep(RETRY_WAIT)
    attempt(id, langs)
  end

  def attempt(id, langs)
    Dir.mktmpdir("ytdlp") do |dir|
      status = run(args_for(id, langs), chdir: dir)
      unless status&.success?
        log_rate_limit(id, status&.stderr)
        next nil
      end

      body = read_subtitle(dir, langs, id)
      body && YoutubeFetcher.flatten_json3(body)
    end
  end

  # The runner records the attempt's status here; only its stderr is needed, to
  # tell a transient 429 from a permanent failure.
  def run(args, chdir:)
    @last_status = runner ? runner.call(args, chdir: chdir) : self.class.exec(args, chdir: chdir, timeout: timeout)
  end

  def rate_limited?
    @last_status&.stderr.to_s.match?(/429|too many requests/i)
  end

  # `--` before the URL, so a URL that somehow started with `-` could not be
  # read as an option. The id is format-validated first, so this is belt and
  # braces.
  def args_for(id, langs)
    args = [
      "--skip-download", "--write-subs", "--write-auto-subs",
      "--sub-format", "json3",
      "--extractor-args", "youtube:player_client=#{self.class.player_client}",
      "--no-playlist", "--no-warnings", "--no-progress", "--no-mtime",
      "--socket-timeout", "10"
    ]
    # No languages means "let yt-dlp pick its default"; passing an empty
    # --sub-langs would request nothing.
    args += [ "--sub-langs", langs.join(",") ] if langs.any?
    args + [ "-o", "sub", "--", "https://www.youtube.com/watch?v=#{id}" ]
  end

  # Each tag is sanitized with the fetcher's own pattern; anything starting with
  # `-` (yt-dlp's exclusion syntax), duplicated or malformed is dropped. The
  # order is preserved because it is the caller's preference order, and the list
  # is capped so a huge page cannot build an unbounded argument.
  def sanitize_languages(languages)
    Array(languages).filter_map do |code|
      tag = code.to_s
      next unless tag.match?(LANGUAGE_CODE)
      next if tag.start_with?("-")

      tag
    end.uniq.first(MAX_LANGUAGES)
  end

  # The `-o sub` template writes every track it downloads, so several
  # `sub.<lang>.json3` files can exist. The language is taken from the exact
  # suffix and matched by equality against the requested list (prefix matching
  # would confuse `pt` with `pt-orig`). Without a preference list, the first
  # file present wins.
  def read_subtitle(dir, langs, id)
    files = Dir.glob(File.join(dir, SUBTITLE_GLOB))
    return log_no_json3(dir, id) if files.empty?

    chosen =
      if langs.empty?
        files.first
      else
        candidates = files.filter_map do |path|
          tag = language_from_filename(path)
          next unless tag

          rank = langs.index(tag)
          rank && [ rank, path ]
        end
        candidates.min_by(&:first)&.last
      end

    # No requested language matched what yt-dlp wrote; fall back to any json3
    # rather than lose a usable transcript.
    chosen ||= files.first
    read_capped(chosen)
  end

  def language_from_filename(path)
    name = File.basename(path).sub(SUBTITLE_SUFFIX, "")
    name.split(".", 2).last.presence
  end

  # A .vtt or .srv3 only means yt-dlp could not honour the json3 preference;
  # this parses json3 only and never tries to parse another subtitle format.
  def log_no_json3(dir, id)
    names = Dir.children(dir)
    if names.any?
      Rails.logger.info("yt-dlp returned no json3 subtitle for #{id}: #{names.join(", ")}")
    end
    nil
  end

  # Read at most the transport's body cap, so a huge caption file is not
  # materialized whole before parsing.
  def read_capped(path)
    File.open(path, "rb") { |file| file.read(HttpTransport::MAX_BODY_BYTES) }
  rescue SystemCallError
    nil
  end

  def log_rate_limit(id, stderr)
    return unless stderr.to_s.match?(/429|too many requests/i)

    Rails.logger.warn("yt-dlp hit a rate limit for #{id}: #{stderr.to_s.strip.lines.first}")
  end

  def log_missing_binary
    return if self.class.missing_binary_logged

    self.class.missing_binary_logged = true
    Rails.logger.warn("yt-dlp is not installed; YouTube transcript fallback is disabled")
  end
end
