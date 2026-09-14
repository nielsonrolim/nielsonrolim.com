require "net/http"

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
    @stdout = stdout
    @stderr = stderr
    @status = FakeStatus.new(success, exitstatus)
    @error = error
    @calls = []
  end

  def exec(*args, timeout: nil)
    @calls << { args: args, timeout: timeout }
    raise @error if @error

    [ @stdout, @stderr, @status ]
  end

  def last_args
    calls.last&.fetch(:args)
  end

  def prompt
    last_args&.at(1)
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
