require "net/http"

# Tests never touch DNS: unless a test injects its own resolver to exercise the
# SSRF guard, every host resolves to this public address.
HttpTransport.resolver = ->(_host) { [ "93.184.216.34" ] }

# Test doubles shared across suites.
#
# Minitest 6 dropped minitest/mock (no Object#stub), so the production code
# exposes injectable seams instead and the fakes live here.

# Builds real Net::HTTPResponse objects, because the transport branches on
# Net::HTTPSuccess / Net::HTTPRedirection.
module HttpResponseHelpers
  RESPONSE_CLASSES = {
    200 => Net::HTTPOK,
    301 => Net::HTTPMovedPermanently,
    302 => Net::HTTPFound,
    404 => Net::HTTPNotFound,
    503 => Net::HTTPServiceUnavailable
  }.freeze

  def http_response(code, body = "", headers = {})
    klass = RESPONSE_CLASSES.fetch(code)
    response = klass.new("1.1", code.to_s, klass.name)
    headers.each { |name, value| response.add_field(name, value) }
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  # Like `http_response`, but readable through `#read_body` the way the real
  # transport streams a body, so the request-building path can be exercised
  # without a socket.
  def streaming_response(code, body = "", headers = {})
    response = http_response(code, body, headers)
    response.instance_variable_set(:@read, false)
    response.define_singleton_method(:read_body) do |&block|
      block ? block.call(body) : body
    end
    response
  end

  # A transport that replays canned responses in order, one per request.
  def transport_returning(*responses)
    queue = responses.dup
    session = lambda do |uri|
      queue.shift || raise(FeedFetcher::Error, "no canned response left for #{uri}")
    end

    HttpTransport.new(session: session)
  end

  # A transport that always returns the same response.
  def transport_always(response)
    HttpTransport.new(session: ->(_uri) { response })
  end
end

# Stands in for OpencodeCli.
class FakeOpencodeCli
  FakeStatus = Struct.new(:success, :exitstatus) do
    def success?
      success
    end
  end

  attr_reader :calls

  def initialize(stdout: "", stderr: "", success: true, exitstatus: 0, error: nil)
    # An Array of stdouts replays one per call, so a test can drive the
    # corrective retry (bad answer, then good) through the same fake.
    @stdout = stdout.is_a?(Array) ? stdout.dup : stdout
    @stderr = stderr
    @status = FakeStatus.new(success, exitstatus)
    @error = error
    @calls = []
  end

  def exec(*args, timeout: nil)
    @calls << { args: args, timeout: timeout }
    raise @error if @error

    [ next_stdout, @stderr, @status ]
  end

  def last_args
    calls.last&.fetch(:args)
  end

  def prompt
    last_args&.at(1)
  end

  private

  def next_stdout
    @stdout.is_a?(Array) ? @stdout.shift.to_s : @stdout
  end
end

# Stands in for SummaryGenerator inside jobs. Returns the same Result shape the
# real generator builds from the model's JSON.
class FakeSummaryGenerator
  attr_reader :calls

  def initialize(result: nil, error: nil)
    @result = result || default_result
    @error = error
    @calls = []
  end

  def call(**kwargs)
    @calls << kwargs
    raise @error if @error

    @result
  end

  private

  def default_result
    SummaryGenerator::Result.new(
      language: "en-US",
      title_translated: "Título traduzido",
      summaries: { "pt-BR" => "Resumo em português.", "en-US" => "Summary in English." }
    )
  end
end

# Stands in for ArticleFetcher inside jobs. Returns the same Result shape the
# real fetcher builds from the page.
class FakeArticleFetcher
  attr_reader :calls

  def initialize(title: "Fetched title", text: "Fetched article body.", error: nil)
    @title = title
    @text = text
    @error = error
    @calls = []
  end

  def call(url)
    @calls << url
    raise @error if @error

    ArticleFetcher::Result.new(title: @title, text: @text)
  end
end

# Stands in for the `YtdlpCli` Open3 runner seam. It writes the scenario's
# subtitle files into the working directory yt-dlp was given, so the real
# `YtdlpCli#call` — arg building, file selection, parsing — runs untouched,
# without a process or a network.
#
# `subtitles` is a Hash of filename => body ("sub.pt-orig.json3" => json3 text),
# written on a successful call. `statuses` can instead be an Array of
# [success, exitstatus, stderr] replayed one per call, to drive the 429 retry.
# `partial:` writes the subtitles even when the call exits non-zero, modelling
# yt-dlp downloading one language and then failing on the next (a 429 on a
# secondary language).
class FakeYtdlpRunner
  attr_reader :calls

  def initialize(subtitles: {}, success: true, exitstatus: 0, stderr: "", statuses: nil, error: nil, partial: false)
    @subtitles = subtitles
    @statuses = statuses
    @default_status = YtdlpCli::Status.new(success, exitstatus, stderr)
    @error = error
    @partial = partial
    @calls = []
  end

  def call(args, chdir:)
    @calls << { args: args, chdir: chdir }
    raise @error if @error

    status = next_status
    if status.success? || @partial
      @subtitles.each { |name, body| File.write(File.join(chdir, name), body) }
    end

    status
  end

  def last_args = calls.last&.fetch(:args)
  def last_chdir = calls.last&.fetch(:chdir)

  private

  def next_status
    return @default_status unless @statuses

    success, exitstatus, stderr = @statuses.shift || [ true, 0, "" ]
    YtdlpCli::Status.new(success, exitstatus, stderr)
  end
end

# Wraps a JSON event stream the way `opencode run --format json` emits it.
module OpencodeEventHelpers
  def opencode_json_output(text, session_id: "ses_test")
    events = [
      { "type" => "step_start", "sessionID" => session_id, "part" => { "type" => "step-start" } },
      { "type" => "text", "sessionID" => session_id, "part" => { "type" => "text", "text" => text } },
      {
        "type" => "step_finish", "sessionID" => session_id,
        "part" => { "type" => "step-finish", "cost" => 0, "tokens" => { "input" => 10, "output" => 5 } }
      }
    ]

    events.map { |event| JSON.generate(event) }.join("\n") + "\n"
  end
end
