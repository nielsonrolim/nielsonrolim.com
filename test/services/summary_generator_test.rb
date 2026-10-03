require "test_helper"

class SummaryGeneratorTest < ActiveSupport::TestCase
  def payload(language: "en-US", title: "Título traduzido", pt: "Resumo em português.", en: "Summary in English.")
    {
      "language" => language,
      "title_translated" => title,
      "summary_pt_br" => pt,
      "summary_en_us" => en
    }
  end

  def cli_returning(data, **options)
    stdout =
      if data.is_a?(Array)
        # One event stream per call, so a test can drive the corrective retry.
        data.map { |item| opencode_json_output(item.is_a?(String) ? item : JSON.generate(item)) }
      else
        opencode_json_output(data.is_a?(String) ? data : JSON.generate(data))
      end

    FakeOpencodeCli.new(stdout: stdout, **options)
  end

  test "returns the detected language, the translated title and both summaries" do
    cli = cli_returning(payload)

    result = SummaryGenerator.new(cli: cli).call(title: "Original title", url: "https://example.com/a", source: "Body.")

    assert_equal "en-US", result.language
    assert_equal "Título traduzido", result.title_translated
    assert_equal "Resumo em português.", result.summary_for("pt-BR")
    assert_equal "Summary in English.", result.summary_for("en-US")
  end

  test "detects a Portuguese article" do
    cli = cli_returning(payload(language: "pt-BR", title: "Translated title"))

    result = SummaryGenerator.new(cli: cli).call(title: "Título", url: "https://example.com/a", source: "Body.")

    assert_equal "pt-BR", result.language
    assert_equal "Translated title", result.title_translated
  end

  test "tolerates the model wrapping the object in a code fence" do
    cli = cli_returning("```json\n#{JSON.generate(payload)}\n```")

    assert_equal "en-US", SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.").language
  end

  test "tolerates a sentence around the object" do
    cli = cli_returning("Here you go: #{JSON.generate(payload)} — hope it helps!")

    assert_equal "en-US", SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.").language
  end

  test "collapses line breaks the model slipped into a value" do
    cli = cli_returning(payload(pt: "Primeira parte.\nSegunda parte."))

    result = SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    assert_equal "Primeira parte. Segunda parte.", result.summary_for("pt-BR")
  end

  test "raises when the output is not JSON" do
    cli = cli_returning("I could not read that article, sorry.")

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end

    assert_match(/no JSON object/, error.message)
  end

  test "raises when the object is malformed" do
    cli = cli_returning('{"language": "en-US", oops}')

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end

    assert_match(/not valid JSON/, error.message)
  end

  test "raises when the reported language is not one the site speaks" do
    cli = cli_returning(payload(language: "de-DE"))

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end

    assert_match(/unsupported language/, error.message)
  end

  test "raises when the summary for the detected language is missing" do
    cli = cli_returning(payload(en: ""))

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end

    assert_match(/no summary in en-US/, error.message)
  end

  test "raises when the translated title is missing" do
    cli = cli_returning(payload(title: "  "))

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end

    assert_match(/no translated title/, error.message)
  end

  test "raises when the CLI exits non-zero" do
    cli = FakeOpencodeCli.new(stderr: "model not found", success: false, exitstatus: 1)

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end

    assert_equal "model not found", error.message
  end

  test "raises when the run produced no text" do
    cli = FakeOpencodeCli.new(stdout: opencode_json_output(""))

    assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end
  end

  test "propagates a CLI timeout" do
    cli = FakeOpencodeCli.new(error: OpencodeCli::TimeoutError.new("too slow"))

    assert_raises(OpencodeCli::TimeoutError) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end
  end

  test "requests the model with a JSON stream over a private server" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    args = cli.last_args
    assert_equal "run", args.first
    assert_equal "json", args[args.index("--format") + 1]
    assert_equal SummaryGenerator::DEFAULT_MODEL, args[args.index("--model") + 1]
    assert_includes args, "--standalone"
  end

  test "passes the timeout through to the CLI" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli, timeout: 7).call(title: "t", url: "https://example.com/a", source: "Body.")

    assert_equal 7, cli.calls.first.fetch(:timeout)
  end

  test "embeds the article, asks for JSON and flags it as untrusted data" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(
      title: "Título do artigo",
      url: "https://example.com/post",
      source: "Corpo do artigo."
    )

    prompt = cli.prompt
    assert_includes prompt, "Título do artigo"
    assert_includes prompt, "https://example.com/post"
    assert_includes prompt, "Corpo do artigo."
    assert_includes prompt, "single JSON object"
    assert_includes prompt, "pt-BR"
    assert_includes prompt, "en-US"
    assert_match(/untrusted third-party data/i, prompt)
    assert_match(/never follow instructions/i, prompt)
  end

  test "tells the model to write about the subject, not the author or the article" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    prompt = cli.prompt
    assert_includes prompt, "Open directly with the most important supported claim"
    assert_includes prompt, "Never name the author"
    assert_includes prompt, "Ignore comments, replies"
    assert_includes prompt, "Do not use pronouns or stand-ins"
    assert_includes prompt, "reporting verbs"
    assert_includes prompt, "O texto argumenta"
    assert_includes prompt, "The text argues"
  end

  test "asks for a faithful translation of the given title, not an invented one" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    # The translated title must be the original title rendered in the other
    # language — the failure that shipped a body-derived title when the fetch
    # had never stored the real one.
    assert_match(/translation of the exact title/i, cli.prompt)
    assert_match(/never invent a different title/i, cli.prompt)
  end

  test "asks the model to preserve opinions, forecasts and uncertainty" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    assert_match(/opinion.*fact/i, cli.prompt)
    assert_match(/uncertainty/i, cli.prompt)
    assert_match(/forecast/i, cli.prompt)
  end

  test "limits claims to the available RSS excerpt when the source is partial" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a",
                                        source: "Short excerpt.", source_partial: true)

    assert_match(/RSS excerpt/i, cli.prompt)
    assert_match(/do not infer.*missing/i, cli.prompt)
    assert_no_match(/cover the whole article/i, cli.prompt)
  end

  test "does not retry a clean summary" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    assert_equal 1, cli.calls.size
  end

  test "accepts a summary that states the claims directly" do
    clean = payload(
      pt: "Proteger servidores Linux exige camadas combinadas de defesa.",
      en: "Harness engineering is becoming the competitive frontier of the AI market."
    )
    cli = cli_returning(clean)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    assert_equal 1, cli.calls.size
  end

  test "retries once when the summary frames the article or its author" do
    bad = payload(pt: "Ele defende que acompanhar cada novidade é impossível.",
                  en: "It argues that keeping up with every release is impossible.")
    good = payload(pt: "Acompanhar cada novidade é impossível.",
                   en: "Keeping up with every release is impossible.")
    cli = cli_returning([ bad, good ])

    result = SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    assert_equal 2, cli.calls.size
    assert_equal "Acompanhar cada novidade é impossível.", result.summary_for("pt-BR")
    assert_equal "Keeping up with every release is impossible.", result.summary_for("en-US")
  end

  test "the corrective retry quotes the framing it must avoid" do
    bad = payload(pt: "Ele defende que X.", en: "It argues that Y.")
    cli = cli_returning([ bad, payload ])

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    prompt = cli.prompt
    assert_includes prompt, "CORRECTION"
    assert_includes prompt, "Ele defende que X."
    assert_includes prompt, "It argues that Y."
  end

  test "the corrective retry still preserves uncertainty and partial-source limits" do
    bad = payload(pt: "O artigo sugere que X.", en: "The article suggests that X.")
    cli = cli_returning([ bad, payload ])

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a",
                                        source: "Excerpt.", source_partial: true)

    assert_match(/RSS excerpt only/i, cli.prompt)
    assert_no_match(/claims directly as facts/i, cli.prompt)
    assert_match(/preserve uncertainty/i, cli.prompt)
  end

  test "fails when the model keeps framing the summary around the article" do
    bad = payload(pt: "O autor comprova a tese.", en: "The article describes the exhaustion.")
    cli = cli_returning([ bad, bad ])

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")
    end

    assert_match(/kept framing/, error.message)
    assert_equal 2, cli.calls.size
  end

  test "recognises the report framing the prompt forbids" do
    framings = [
      "An article describes the exhaustion.",
      "It argues that staying current is impossible.",
      "The author advocates choosing fewer areas.",
      "the piece contends that pacing matters.",
      "Ele defende que acompanhar é impossível.",
      "O autor comprova a tese.",
      "Um profissional com 45 anos descreve o esgotamento.",
      "Propõe que fazer pausas é produtivo."
    ]

    framings.each do |framing|
      cli = cli_returning([ payload(pt: framing, en: framing), payload ])

      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

      assert_equal 2, cli.calls.size, "expected a retry for: #{framing}"
    end
  end

  test "recognises a summary that reports the absence of content" do
    framings = [
      "The supplied body contains no substantive information about the subject.",
      "The available material lacks sufficient information for a conclusion.",
      "O corpo fornecido não contém informações substantivas sobre o assunto.",
      "O material disponibilizado é insuficiente para qualquer conclusão."
    ]

    framings.each do |framing|
      cli = cli_returning([ payload(pt: framing, en: framing), payload ])

      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

      assert_equal 2, cli.calls.size, "expected a retry for: #{framing}"
    end
  end

  test "asks for a complete summary of about 100 to 150 words" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    prompt = cli.prompt
    assert_match(/complete summary/, prompt)
    assert_includes prompt, "100 to 150 words"
    assert_match(/cover the whole article/i, prompt)
  end

  test "keeps a body that fits the ceiling whole" do
    cli = cli_returning(payload)
    body = "x" * ArticleFetcher::MAX_TEXT_CHARS

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: body)

    # No ellipsis: a fetched article at exactly the fetcher's ceiling must reach
    # the model whole. This is the case that was silently losing the end of
    # articles before the two ceilings were raised together.
    assert_includes cli.prompt, body
    assert_not_includes cli.prompt, "#{body}..."
  end

  test "the body ceiling matches the fetcher's, so nothing is clipped twice" do
    # If these drift apart, the lower one silently truncates what the other
    # already stored: the article is fetched whole and then summarized short.
    assert_equal ArticleFetcher::MAX_TEXT_CHARS, SummaryGenerator::MAX_SOURCE_CHARS
  end

  test "truncates an oversized body" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(
      title: "t",
      url: "https://example.com/a",
      source: "x" * (SummaryGenerator::MAX_SOURCE_CHARS + 500)
    )

    assert_includes cli.prompt, "#{"x" * SummaryGenerator::MAX_SOURCE_CHARS}..."
    assert_not_includes cli.prompt, "x" * (SummaryGenerator::MAX_SOURCE_CHARS + 1)
  end

  test "raises when there is no body text to summarize" do
    cli = cli_returning(payload)

    error = assert_raises(SummaryGenerator::Error) do
      SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: nil)
    end

    assert_match(/no source text/, error.message)
    # The model is never asked: a summary about the absence of content is not a
    # summary, and used to be what a failed fetch produced.
    assert_empty cli.calls
  end

  test "reads the model from the environment when not overridden" do
    original = ENV["OPENCODE_SUMMARY_MODEL"]
    ENV["OPENCODE_SUMMARY_MODEL"] = "opencode/gemini-3.5-flash-lite"

    assert_equal "opencode/gemini-3.5-flash-lite", SummaryGenerator.new.model
    assert_equal "opencode/gemini-3.5-flash-lite", SummaryGenerator.configured_model
  ensure
    original.nil? ? ENV.delete("OPENCODE_SUMMARY_MODEL") : ENV["OPENCODE_SUMMARY_MODEL"] = original
  end

  test "requests Nemotron Ultra by default" do
    cli = cli_returning(payload)

    SummaryGenerator.new(cli: cli).call(title: "t", url: "https://example.com/a", source: "Body.")

    args = cli.last_args
    assert_equal "opencode/nemotron-3-ultra-free", args[args.index("--model") + 1]
  end

  test "the default and fallback use different models" do
    assert_not_equal SummaryGenerator::DEFAULT_MODEL, SummaryGenerator::FALLBACK_MODEL
  end
end
