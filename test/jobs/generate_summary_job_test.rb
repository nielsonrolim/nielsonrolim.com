require "test_helper"

class GenerateSummaryJobTest < ActiveJob::TestCase
  # Records the clipping's status at the moment the model is invoked, so the
  # intermediate "summarizing" state can be asserted.
  class StatusObserver
    attr_reader :status_seen

    def initialize(clipping)
      @clipping = clipping
    end

    def call(**)
      @status_seen = @clipping.reload.summary_status
      SummaryGenerator::Result.new(
        language: "en-US",
        title_translated: "Título traduzido",
        summaries: { "pt-BR" => "Resumo em português.", "en-US" => "Summary in English." }
      )
    end
  end

  def result(language: "en-US", title: "Título traduzido", pt: "Resumo em português.", en: "Summary in English.")
    SummaryGenerator::Result.new(
      language: language,
      title_translated: title,
      summaries: { "pt-BR" => pt, "en-US" => en }
    )
  end

  setup do
    @clipping = clippings(:pending)
  end

  test "stores the detected language, the translated title and both summaries" do
    @clipping.update_columns(summary_status: "failed", summary_error: "boom")

    perform_with(FakeSummaryGenerator.new(result: result))

    @clipping.reload
    assert @clipping.summarized?
    assert_equal "en-US", @clipping.variant_for("en-US").locale
    assert_equal "Título traduzido", @clipping.title_for("pt-BR")
    # The summary in the article's own language lands on its edition.
    assert_equal "Summary in English.", @clipping.summary_for("en-US")
    assert_equal "Resumo em português.", @clipping.summary_for("pt-BR")
    # The pt-BR variant is only a translation: no URL of its own.
    assert_nil @clipping.variant_for("pt-BR").url
    assert_equal "https://example.com/solid-queue", @clipping.url_for("pt-BR")
    assert_nil @clipping.summary_error
  end

  test "keeps the original title on the source edition" do
    original = @clipping.display_title

    perform_with(FakeSummaryGenerator.new(result: result))

    assert_equal original, @clipping.reload.title_for("en-US")
  end

  test "maps the summaries the right way round for a Portuguese article" do
    perform_with(FakeSummaryGenerator.new(result: result(language: "pt-BR", pt: "Resumo em pt.", en: "English summary.")))

    @clipping.reload
    assert_equal "pt-BR", @clipping.variant_for("pt-BR").locale
    assert_equal "English summary.", @clipping.summary_for("en-US")
    assert_equal "Resumo em pt.", @clipping.summary_for("pt-BR")
  end

  test "uses the stored article text when there is no feed entry" do
    clipping = Clipping.new(source_text: "texto colado à mão")
    clipping.variants.build(url: "https://example.com/manual", title: "Manual")
    clipping.save!

    generator = FakeSummaryGenerator.new
    job_with(generator, clipping_id: clipping.id).perform_now

    assert_equal "texto colado à mão", generator.calls.first[:source]
  end

  test "fetches the article and uses the full text as the source" do
    fetcher = FakeArticleFetcher.new(text: "Corpo completo do artigo.")
    generator = FakeSummaryGenerator.new
    perform_with(generator, fetcher: fetcher)

    assert_equal [ @clipping.primary_variant.url ], fetcher.calls
    assert_equal "Corpo completo do artigo.", generator.calls.first[:source]
    assert_equal "Corpo completo do artigo.", @clipping.reload.source_text
    assert_equal @clipping.display_title, generator.calls.first[:title]
    assert_equal @clipping.primary_variant.url, generator.calls.first[:url]
  end

  test "falls back to the feed summary when the fetch fails" do
    fetcher = FakeArticleFetcher.new(error: ArticleFetcher::Error.new("blocked bot"))
    generator = FakeSummaryGenerator.new

    perform_with(generator, fetcher: fetcher)

    assert_equal entries(:solid_queue).summary, generator.calls.first[:source]
    assert_nil @clipping.reload.source_text
    assert @clipping.summarized?
  end

  test "does not fetch again when the text is already stored" do
    @clipping.update!(source_text: "texto já guardado")
    fetcher = FakeArticleFetcher.new
    generator = FakeSummaryGenerator.new

    perform_with(generator, fetcher: fetcher)

    assert_empty fetcher.calls
    assert_equal "texto já guardado", generator.calls.first[:source]
  end

  test "marks the clipping as summarizing while the model runs" do
    observer = StatusObserver.new(@clipping)
    perform_with(observer)

    assert_equal "summarizing", observer.status_seen
    assert @clipping.reload.summarized?
  end

  test "retries with an incremented attempt when generation fails" do
    assert_enqueued_with(job: GenerateSummaryJob, args: [ @clipping.id, 2 ]) do
      job_with(FakeSummaryGenerator.new(error: SummaryGenerator::Error.new("boom")), attempt: 1).perform_now
    end

    assert_not @clipping.reload.failed?
  end

  test "marks the clipping failed once the attempts run out" do
    assert_no_enqueued_jobs(only: GenerateSummaryJob) do
      failing_job(attempt: GenerateSummaryJob::MAX_ATTEMPTS).perform_now
    end

    @clipping.reload
    assert @clipping.failed?
    assert_equal "still broken", @clipping.summary_error
    assert_nil @clipping.summary_for("en-US")
    # The language was never detected, so the source edition has no locale yet.
    assert_nil @clipping.source_variant.locale
  end

  test "truncates a long error message" do
    job_with(FakeSummaryGenerator.new(error: SummaryGenerator::Error.new("x" * 900)),
             attempt: GenerateSummaryJob::MAX_ATTEMPTS).perform_now

    assert_equal 500, @clipping.reload.summary_error.length
  end

  test "a CLI timeout is retried like any other generation failure" do
    generator = FakeSummaryGenerator.new(error: OpencodeCli::TimeoutError.new("too slow"))

    assert_enqueued_with(job: GenerateSummaryJob, args: [ @clipping.id, 2 ]) do
      job_with(generator, attempt: 1).perform_now
    end
  end

  test "ignores a clipping that no longer exists" do
    generator = FakeSummaryGenerator.new

    assert_nothing_raised { job_with(generator, clipping_id: -1).perform_now }
    assert_empty generator.calls
  end

  private

  # Rails 8.1: job arguments go to `new`, and the instance `perform_now` takes none.
  def perform_with(generator, attempt: 1, fetcher: FakeArticleFetcher.new)
    job_with(generator, attempt: attempt, fetcher: fetcher).perform_now
  end

  def job_with(generator, attempt: 1, clipping_id: @clipping.id, fetcher: FakeArticleFetcher.new)
    job = GenerateSummaryJob.new(clipping_id, attempt)
    job.summary_generator = generator
    job.article_fetcher = fetcher
    job
  end

  def failing_job(attempt:)
    job_with(FakeSummaryGenerator.new(error: SummaryGenerator::Error.new("still broken")), attempt: attempt)
  end
end
