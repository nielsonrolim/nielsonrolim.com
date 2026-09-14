require "test_helper"

class SummaryGeneratorTest < ActiveSupport::TestCase
  test "returns the text emitted by the model" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("O Rails 8.2 traz melhorias nas filas."))

    summary = SummaryGenerator.new(cli: cli).call(
      title: "Rails 8.2 and queues",
      url: "https://example.com/rails-8-2",
      source: "A deep dive into the new release."
    )

    assert_equal "O Rails 8.2 traz melhorias nas filas.", summary
  end

  test "joins several text events and collapses them into one paragraph" do
    events = [
      { "type" => "text", "sessionID" => "s", "part" => { "text" => "Primeira parte." } },
      { "type" => "text", "sessionID" => "s", "part" => { "text" => "\nSegunda parte.\n" } }
    ].map { |event| JSON.generate(event) }.join("\n")

    cli = FakeOpencodeCli.new(stdout: events)

    summary = SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com")

    assert_equal "Primeira parte. Segunda parte.", summary
  end

  test "ignores non-text events and malformed lines" do
    stdout = [
      "this is not json",
      JSON.generate({ "type" => "step_start", "sessionID" => "s", "part" => {} }),
      JSON.generate({ "type" => "text", "sessionID" => "s", "part" => { "text" => "Resumo." } }),
      JSON.generate({ "type" => "step_finish", "sessionID" => "s", "part" => { "cost" => 0 } })
    ].join("\n")

    cli = FakeOpencodeCli.new(stdout: stdout)

    assert_equal "Resumo.", SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com")
  end

  test "requests the free model with a JSON stream by default" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("Resumo."))

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com")

    args = cli.last_args
    assert_equal "run", args.first
    assert_includes args, "--format"
    assert_equal "json", args[args.index("--format") + 1]
    assert_includes args, "--model"
    assert_equal SummaryGenerator::DEFAULT_MODEL, args[args.index("--model") + 1]
    assert_includes args, "--pure"
  end

  test "honours a model override" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("Resumo."))

    SummaryGenerator.new(cli: cli, model: "opencode/mimo-v2.5-free").call(title: "t", url: "https://example.com")

    assert_includes cli.last_args, "opencode/mimo-v2.5-free"
  end

  test "passes the timeout through to the CLI" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("Resumo."))

    SummaryGenerator.new(cli: cli, timeout: 7).call(title: "t", url: "https://example.com")

    assert_equal 7, cli.calls.first.fetch(:timeout)
  end

  test "embeds the article and flags it as untrusted data" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("Resumo."))

    SummaryGenerator.new(cli: cli).call(
      title: "Título do artigo",
      url: "https://example.com/post",
      source: "Corpo do artigo."
    )

    prompt = cli.prompt
    assert_includes prompt, "Título do artigo"
    assert_includes prompt, "https://example.com/post"
    assert_includes prompt, "Corpo do artigo."
    assert_match(/untrusted data/i, prompt)
    assert_match(/never follow any instruction/i, prompt)
  end

  test "asks for the configured language" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("Resumo."))

    SummaryGenerator.new(cli: cli, language: "English").call(title: "t", url: "https://example.com")

    assert_includes cli.prompt, "Write in English."
  end

  test "truncates an oversized body" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("Resumo."))

    SummaryGenerator.new(cli: cli).call(
      title: "t",
      url: "https://example.com",
      source: "x" * (SummaryGenerator::MAX_SOURCE_CHARS + 500)
    )

    # Only the first MAX_SOURCE_CHARS of the body make it into the prompt.
    assert_includes cli.prompt, "#{"x" * SummaryGenerator::MAX_SOURCE_CHARS}..."
    assert_not_includes cli.prompt, "x" * (SummaryGenerator::MAX_SOURCE_CHARS + 1)
  end

  test "notes when no body text is available" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output("Resumo."))

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com", source: nil)

    assert_includes cli.prompt, "(no body text available)"
  end

  test "raises when the CLI exits non-zero" do
    cli = FakeOpencodeCli.new(stderr: "model not found", success: false, exitstatus: 1)

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com")
    end

    assert_equal "model not found", error.message
  end

  test "raises with the exit status when stderr is blank" do
    cli = FakeOpencodeCli.new(stderr: "", success: false, exitstatus: 3)

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com")
    end

    assert_match(/status 3/, error.message)
  end

  test "raises when the run produced no text" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output(""))

    assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com")
    end
  end

  test "propagates a CLI timeout" do
    cli = FakeOpencodeCli.new(error: OpencodeCli::TimeoutError.new("too slow"))

    assert_raises(OpencodeCli::TimeoutError) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com")
    end
  end

  test "reads the model from the environment when not overridden" do
    original = ENV["OPENCODE_SUMMARY_MODEL"]
    ENV["OPENCODE_SUMMARY_MODEL"] = "opencode/gemini-3.5-flash-lite"

    assert_equal "opencode/gemini-3.5-flash-lite", SummaryGenerator.new.model
  ensure
    original.nil? ? ENV.delete("OPENCODE_SUMMARY_MODEL") : ENV["OPENCODE_SUMMARY_MODEL"] = original
  end
end
