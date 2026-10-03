require "test_helper"

class FetchSourceTextJobTest < ActiveJob::TestCase
  # Records the clipping's status while the fetch runs, so the intermediate
  # "fetching" state can be asserted.
  class StatusObserver
    attr_reader :status_seen

    def initialize(clipping)
      @clipping = clipping
    end

    def call(_url)
      @status_seen = @clipping.reload.summary_status
      ArticleFetcher::Result.new(title: "Fetched title", text: "Fetched body.")
    end
  end

  setup do
    @clipping = clippings(:pending)
  end

  test "stores the fetched text and hands off to the summary" do
    fetcher = FakeArticleFetcher.new(text: "Corpo completo.")

    assert_enqueued_with(job: GenerateSummaryJob, args: [ @clipping.id, 1, false ]) do
      job_with(fetcher).perform_now
    end

    assert_equal "Corpo completo.", @clipping.reload.source_text
    assert_equal [ @clipping.primary_variant.url ], fetcher.calls
  end

  test "asks the fetcher for the primary variant's url" do
    fetcher = FakeArticleFetcher.new

    job_with(fetcher).perform_now

    assert_equal [ "https://example.com/solid-queue" ], fetcher.calls
  end

  test "replaces the host placeholder title with the fetched one" do
    clipping = manual_clipping(title: "example.com")
    fetcher = FakeArticleFetcher.new(title: "Uma manchete de verdade", text: "Corpo.")

    job_with(fetcher, clipping: clipping).perform_now

    assert_equal "Uma manchete de verdade", clipping.reload.primary_variant.title
  end

  test "keeps a title the reader typed" do
    clipping = manual_clipping(title: "Meu título")
    fetcher = FakeArticleFetcher.new(title: "Uma manchete de verdade")

    job_with(fetcher, clipping: clipping).perform_now

    assert_equal "Meu título", clipping.reload.primary_variant.title
  end

  test "keeps a feed clipping's entry title" do
    fetcher = FakeArticleFetcher.new(title: "Título buscado")

    job_with(fetcher).perform_now

    assert_equal "Understanding Solid Queue internals", @clipping.reload.primary_variant.title
  end

  test "marks the clipping as fetching while the fetch runs" do
    observer = StatusObserver.new(@clipping)

    job_with(observer).perform_now

    assert_equal "fetching", observer.status_seen
  end

  test "still hands off to the summary when the fetch fails" do
    fetcher = FakeArticleFetcher.new(error: ArticleFetcher::Error.new("blocked bot"))

    assert_enqueued_with(job: GenerateSummaryJob, args: [ @clipping.id, 1, false ]) do
      job_with(fetcher).perform_now
    end

    # Nothing stored; the feed excerpt still gives the summary a source.
    assert_nil @clipping.reload.source_text
  end

  test "does not fetch when the text is already stored" do
    @clipping.update!(source_text: "texto já guardado")
    fetcher = FakeArticleFetcher.new

    assert_enqueued_with(job: GenerateSummaryJob, args: [ @clipping.id, 1, false ]) do
      job_with(fetcher).perform_now
    end

    assert_empty fetcher.calls
    assert_equal "texto já guardado", @clipping.reload.source_text
  end

  test "force re-fetches over stored text" do
    @clipping.update!(source_text: "texto antigo")
    fetcher = FakeArticleFetcher.new(text: "texto novo")

    job_with(fetcher, force: true).perform_now

    assert_equal [ @clipping.primary_variant.url ], fetcher.calls
    assert_equal "texto novo", @clipping.reload.source_text
  end

  test "a clipping with no url is left alone but still hands off" do
    clipping = Clipping.new(source_name: "example.com", summary_status: :pending)
    clipping.variants.build(title: "Sem URL", origin: :generated)
    clipping.save!
    fetcher = FakeArticleFetcher.new

    assert_enqueued_with(job: GenerateSummaryJob, args: [ clipping.id, 1, false ]) do
      job_with(fetcher, clipping: clipping).perform_now
    end

    assert_empty fetcher.calls
    assert_nil clipping.reload.source_text
  end

  test "ignores a clipping that no longer exists" do
    fetcher = FakeArticleFetcher.new

    assert_nothing_raised { job_with(fetcher, clipping_id: -1).perform_now }
    assert_empty fetcher.calls
  end

  private

  # A hand-added clipping, as the create form leaves it: no entry, its source
  # edition carrying the URL and (when nothing was typed) the host as a stand-in
  # title.
  def manual_clipping(title:, url: "https://example.com/story")
    clipping = Clipping.new(source_name: "example.com", summary_status: :pending)
    clipping.variants.build(url: url, title: title, origin: :generated)
    clipping.save!
    clipping
  end

  def job_with(fetcher, clipping: @clipping, clipping_id: nil, force: false, chain_summary: true, overwrite: false)
    job = FetchSourceTextJob.new(clipping_id || clipping.id, force: force,
                                 chain_summary: chain_summary, overwrite: overwrite)
    job.article_fetcher = fetcher
    job
  end
end
