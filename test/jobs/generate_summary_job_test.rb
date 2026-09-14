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
    assert_equal "en-US", @clipping.language
    assert_equal "Título traduzido", @clipping.title_translated
    # `summary` is the one in the article's own language.
    assert_equal "Summary in English.", @clipping.summary
    assert_equal "Resumo em português.", @clipping.summary_translated
    assert_nil @clipping.summary_error
  end

  test "keeps the original title untouched" do
    original = @clipping.title

    perform_with(FakeSummaryGenerator.new(result: result))

    assert_equal original, @clipping.reload.title
  end

  test "maps the summaries the right way round for a Portuguese article" do
    perform_with(FakeSummaryGenerator.new(result: result(language: "pt-BR", pt: "Resumo em pt.", en: "English summary.")))

    @clipping.reload
    assert_equal "pt-BR", @clipping.language
    assert_equal "Resumo em pt.", @clipping.summary
    assert_equal "English summary.", @clipping.summary_translated
    assert_equal "English summary.", @clipping.summary_for("en-US")
    assert_equal "Resumo em pt.", @clipping.summary_for("pt-BR")
  end

  test "passes the title, URL and the entry summary as source" do
    generator = FakeSummaryGenerator.new
    perform_with(generator)

    kwargs = generator.calls.first
    assert_equal @clipping.title, kwargs[:title]
    assert_equal @clipping.url, kwargs[:url]
    assert_equal entries(:solid_queue).summary, kwargs[:source]
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
    assert_nil @clipping.summary
    assert_nil @clipping.language
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
  def perform_with(generator, attempt: 1)
    job_with(generator, attempt: attempt).perform_now
  end

  def job_with(generator, attempt: 1, clipping_id: @clipping.id)
    job = GenerateSummaryJob.new(clipping_id, attempt)
    job.summary_generator = generator
    job
  end

  def failing_job(attempt:)
    job_with(FakeSummaryGenerator.new(error: SummaryGenerator::Error.new("still broken")), attempt: attempt)
  end
end
