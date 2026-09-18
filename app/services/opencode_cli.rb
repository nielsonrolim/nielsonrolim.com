require "open3"
require "timeout"

# Thin wrapper around the `opencode` CLI.
#
# Every invocation runs with a locked-down config that denies all tools. The
# prompts we send embed text scraped from third-party feeds, so a prompt
# injection attempt hidden in an article must never be able to reach a shell, a
# file edit or a network fetch.
class OpencodeCli
  LOCKED_CONFIG = Rails.root.join("config/opencode/summarizer.json").to_s

  # Deterministic, tool-free run. `OPENCODE_CONFIG` points at our locked config
  # and `OPENCODE_DISABLE_PROJECT_CONFIG` keeps the project's own opencode.json
  # from loosening permissions. On opencode v2 the caller must also pass
  # `--standalone` (see SummaryGenerator#call): without it the run attaches to
  # the shared background server, whose config our env cannot override.
  BASE_ENV = {
    "OPENCODE_CONFIG" => LOCKED_CONFIG,
    "OPENCODE_DISABLE_PROJECT_CONFIG" => "1",
    "OPENCODE_DISABLE_EXTERNAL_SKILLS" => "1",
    "OPENCODE_DISABLE_CLAUDE_CODE_SKILLS" => "1"
  }.freeze

  DEFAULT_TIMEOUT = 180

  class TimeoutError < StandardError; end

  # Runs `opencode` with the given arguments.
  # Returns [stdout, stderr, status]. Raises TimeoutError if it overruns.
  def self.exec(*args, timeout: DEFAULT_TIMEOUT)
    # pgroup so a timeout can take down opencode *and* anything it spawned.
    Open3.popen3(BASE_ENV, "opencode", *args, chdir: Rails.root.to_s, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      stdin.close

      # Read both pipes concurrently: reading them in sequence would deadlock
      # once either filled its OS pipe buffer.
      readers = [ Thread.new { stdout.read }, Thread.new { stderr.read } ]

      begin
        ::Timeout.timeout(timeout) do
          out, err = readers.map(&:value)
          return [ out, err, wait_thr.value ]
        end
      rescue ::Timeout::Error
        readers.each { |reader| reader.kill }
        kill_process_group(wait_thr.pid)
        raise TimeoutError, "opencode did not finish within #{timeout}s"
      end
    end
  end

  # Takes down opencode and anything it spawned. The direct child is left for
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
end
