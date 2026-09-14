require "test_helper"

class ClippingTest < ActiveSupport::TestCase
  test "requires a title and a URL" do
    clipping = Clipping.new(entry: entries(:front_page))

    assert_not clipping.valid?
    assert_includes clipping.errors.attribute_names, :title
    assert_includes clipping.errors.attribute_names, :url
  end

  test "rejects a URL that is not http(s)" do
    clipping = Clipping.new(entry: entries(:front_page), title: "t", url: "javascript:alert(1)")

    assert_not clipping.valid?
    assert_includes clipping.errors.attribute_names, :url
  end

  test "enqueues summary generation as soon as it is marked" do
    assert_enqueued_with(job: GenerateSummaryJob) do
      Clipping.create!(entry: entries(:front_page), title: "t", url: "https://example.com/x")
    end
  end

  test "starts out pending, with no summary" do
    clipping = Clipping.create!(entry: entries(:front_page), title: "t", url: "https://example.com/x")

    assert clipping.pending?
    assert_nil clipping.summary
  end

  test "refuses to queue the same entry twice while unsent" do
    existing = clippings(:queued)

    duplicate = Clipping.new(entry: existing.entry, title: existing.title, url: existing.url)
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :entry

    # The partial unique index backs the validation up against races.
    assert_raises(ActiveRecord::RecordNotUnique) do
      Clipping.insert!({ entry_id: existing.entry_id, title: "t", url: "https://example.com/dup",
                         summary_status: "pending", created_at: Time.current, updated_at: Time.current })
    end
  end

  test "can be clipped again once the previous clipping has been sent" do
    sent = clippings(:sent)
    assert_not_nil sent.newsletter_id

    assert_difference -> { Clipping.count }, 1 do
      Clipping.create!(entry: sent.entry, title: sent.title, url: sent.url)
    end
  end

  test "unsent only returns clippings that have no issue yet" do
    assert_includes Clipping.unsent, clippings(:queued)
    assert_includes Clipping.unsent, clippings(:pending)
    assert_not_includes Clipping.unsent, clippings(:sent)
  end

  test "the languages are the site's locales" do
    assert_equal %w[pt-BR en-US], Clipping::LANGUAGES
  end

  test "rejects a language the site does not speak" do
    clipping = Clipping.new(entry: entries(:front_page), title: "t",
                            url: "https://example.com/x", language: "de-DE")

    assert_not clipping.valid?
    assert_includes clipping.errors.attribute_names, :language
  end

  test "title_for and summary_for follow the detected language" do
    clipping = clippings(:queued) # written in en-US

    assert_equal "Rails 8.1 ships with a new queue UI", clipping.title_for("en-US")
    assert_equal "O Rails 8.1 traz uma nova interface de filas", clipping.title_for("pt-BR")
    assert_equal "Solid Queue is a database-backed adapter for Active Job.", clipping.summary_for("en-US")
    assert_equal "O Rails 8.1 traz um novo painel de filas.", clipping.summary_for("pt-BR")
  end

  test "title_for falls back to the original when nothing is translated" do
    clipping = clippings(:pending)

    assert_nil clipping.language
    assert_equal clipping.title, clipping.title_for("pt-BR")
    assert_equal clipping.title, clipping.title_for("en-US")
  end

  test "other_locale is the language that is not the detected one" do
    assert_equal "pt-BR", clippings(:queued).other_locale
    assert_nil clippings(:pending).other_locale
  end

  test "translated? is false until a translation exists" do
    assert clippings(:queued).translated?
    assert_not clippings(:pending).translated?
  end

  test "apply_summary stores the result and keeps the original title" do
    clipping = clippings(:pending)
    original_title = clipping.title

    clipping.apply_summary(
      SummaryGenerator::Result.new(
        language: "pt-BR",
        title_translated: "Understanding Solid Queue internals (EN)",
        summaries: { "pt-BR" => "Resumo em português.", "en-US" => "Summary in English." }
      )
    )

    assert_equal "pt-BR", clipping.language
    assert_equal original_title, clipping.title
    assert_equal "Understanding Solid Queue internals (EN)", clipping.title_translated
    # `summary` is the article's own language; the other is the translation.
    assert_equal "Resumo em português.", clipping.summary
    assert_equal "Summary in English.", clipping.summary_translated
    assert clipping.summarized?
    assert_nil clipping.summary_error
  end
end
