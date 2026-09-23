require "test_helper"

class ClippingTest < ActiveSupport::TestCase
  def build_clipping(attributes = {})
    clipping = Clipping.new
    clipping.variants.build(url: "https://example.com/x", title: "t")
    clipping.assign_attributes(attributes)
    clipping
  end

  test "requires at least one language edition" do
    clipping = Clipping.new(entry: entries(:front_page))

    assert_not clipping.valid?
    assert_includes clipping.errors.attribute_names, :variants
  end

  test "enqueues summary generation as soon as it is marked" do
    assert_enqueued_with(job: GenerateSummaryJob) do
      build_clipping(entry: entries(:front_page)).save!
    end
  end

  test "starts out pending, with no summary" do
    clipping = build_clipping(entry: entries(:front_page))
    clipping.save!

    assert clipping.pending?
    assert_nil clipping.summary_for("en-US")
  end

  test "refuses to queue the same entry twice while unsent" do
    existing = clippings(:queued)

    duplicate = Clipping.new(entry: existing.entry)
    duplicate.variants.build(url: "https://example.com/dup", title: "t")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :entry

    # The partial unique index backs the validation up against races.
    assert_raises(ActiveRecord::RecordNotUnique) do
      Clipping.insert!({ entry_id: existing.entry_id, summary_status: "pending",
                         created_at: Time.current, updated_at: Time.current })
    end
  end

  test "can be clipped again once the previous clipping has been sent" do
    sent = clippings(:sent)
    assert_not_nil sent.newsletter_id

    assert_difference -> { Clipping.count }, 1 do
      clipping = Clipping.new(entry: sent.entry)
      clipping.variants.build(url: "https://example.com/again", title: "t")
      clipping.save!
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

  test "title_for and summary_for follow the edition for each language" do
    clipping = clippings(:queued) # written in en-US, with a pt-BR edition

    assert_equal "Rails 8.1 ships with a new queue UI", clipping.title_for("en-US")
    assert_equal "O Rails 8.1 traz uma nova interface de filas", clipping.title_for("pt-BR")
    assert_equal "Solid Queue is a database-backed adapter for Active Job.", clipping.summary_for("en-US")
    assert_equal "O Rails 8.1 traz um novo painel de filas.", clipping.summary_for("pt-BR")
  end

  test "title_for and url_for fall back to the primary edition" do
    clipping = clippings(:pending)

    assert_equal clipping.display_title, clipping.title_for("pt-BR")
    assert_equal clipping.display_title, clipping.title_for("en-US")
    assert_equal clipping.url_for("pt-BR"), clipping.url_for("en-US")
  end

  test "summary_for never falls back to another language" do
    clipping = clippings(:pending)

    assert_nil clipping.summary_for("pt-BR")
    assert_nil clipping.summary_for("en-US")
  end

  test "url_for uses the edition's own URL when it has one" do
    clipping = clippings(:queued)
    clipping.variant_for("pt-BR").update!(url: "https://example.com/rails-8-1-pt")

    assert_equal "https://example.com/rails-8-1", clipping.url_for("en-US")
    assert_equal "https://example.com/rails-8-1-pt", clipping.url_for("pt-BR")
  end

  test "url_for falls back to the source edition when a translation has no URL" do
    clipping = clippings(:single)

    assert_equal "https://example.com/single", clipping.url_for("en-US")
    assert_equal "https://example.com/single", clipping.url_for("pt-BR")
    # The translated text still goes out, over the source link.
    assert_equal "Uma história em um idioma só", clipping.title_for("pt-BR")
    assert_equal "Resumo em português.", clipping.summary_for("pt-BR")
  end

  test "languages lists only the editions published with a URL" do
    assert_equal %w[pt-BR en-US], clippings(:queued).languages
    # The pt-BR variant is only a translation, so the story is not in pt-BR.
    assert_equal %w[en-US], clippings(:single).languages
    assert_equal [], clippings(:pending).languages
  end

  test "primary_variant is a published edition" do
    assert_equal "en-US", clippings(:queued).primary_variant.locale

    pending = clippings(:pending)
    assert_nil pending.primary_variant.locale
    assert_equal "Understanding Solid Queue internals", pending.primary_variant.title
  end

  test "source_variant is the edition before the language is detected" do
    assert_nil clippings(:pending).source_variant.locale
    assert_nil clippings(:queued).source_variant
  end

  test "stored_variant shows the source edition under the first locale" do
    pending = clippings(:pending)

    assert_equal clippings(:pending).primary_variant, pending.stored_variant("pt-BR")
    assert_nil pending.stored_variant("en-US")
  end

  test "apply_summary stores the result as generated editions" do
    clipping = build_clipping(entry: entries(:front_page))

    clipping.apply_summary(
      SummaryGenerator::Result.new(
        language: "pt-BR",
        title_translated: "Understanding Solid Queue internals (EN)",
        summaries: { "pt-BR" => "Resumo em português.", "en-US" => "Summary in English." }
      )
    )
    clipping.save!

    # The original title is kept as the source edition's own title.
    assert_equal "t", clipping.title_for("pt-BR")
    assert_equal "Resumo em português.", clipping.summary_for("pt-BR")
    assert_equal "Understanding Solid Queue internals (EN)", clipping.title_for("en-US")
    assert_equal "Summary in English.", clipping.summary_for("en-US")
    assert_equal "generated", clipping.variant_for("en-US").origin
    assert clipping.summarized?
    assert_nil clipping.summary_error
  end

  test "apply_summary never writes a URL, so a translation has none" do
    clipping = build_clipping(entry: entries(:front_page))

    clipping.apply_summary(
      SummaryGenerator::Result.new(
        language: "pt-BR",
        title_translated: "Understanding Solid Queue internals (EN)",
        summaries: { "pt-BR" => "Resumo em português.", "en-US" => "Summary in English." }
      )
    )
    clipping.save!

    assert_equal "https://example.com/x", clipping.variant_for("pt-BR").url
    assert_nil clipping.variant_for("en-US").url
    # Readers of the translation still get a working link.
    assert_equal "https://example.com/x", clipping.url_for("en-US")
  end

  test "apply_summary keeps a URL already set on the other edition" do
    clipping = clippings(:queued)
    clipping.variant_for("pt-BR").update!(url: "https://example.com/rails-8-1-pt")

    clipping.apply_summary(
      SummaryGenerator::Result.new(
        language: "en-US",
        title_translated: "Outro título",
        summaries: { "pt-BR" => "Resumo novo.", "en-US" => "Summary new." }
      )
    )
    clipping.save!

    assert_equal "https://example.com/rails-8-1-pt", clipping.variant_for("pt-BR").url
  end

  test "apply_summary never overwrites a manual edition" do
    clipping = clippings(:queued)
    clipping.variant_for("pt-BR").update!(origin: :manual, title: "Meu título", summary: "Meu resumo")

    clipping.apply_summary(
      SummaryGenerator::Result.new(
        language: "en-US",
        title_translated: "Novo título",
        summaries: { "pt-BR" => "Resumo novo.", "en-US" => "Summary new." }
      )
    )
    clipping.save!

    assert_equal "Meu título", clipping.title_for("pt-BR")
    assert_equal "Meu resumo", clipping.summary_for("pt-BR")
    # The generated en-US edition still gets refreshed.
    assert_equal "Rails 8.1 ships with a new queue UI", clipping.title_for("en-US")
    assert_equal "Summary new.", clipping.summary_for("en-US")
  end

  test "apply_summary moves the source edition to the detected language" do
    clipping = clippings(:pending)

    clipping.apply_summary(
      SummaryGenerator::Result.new(
        language: "en-US",
        title_translated: "Título",
        summaries: { "pt-BR" => "Resumo.", "en-US" => "Summary." }
      )
    )
    clipping.save!

    assert_nil clipping.source_variant
    assert_equal "en-US", clipping.variant_for("en-US").locale
    assert_equal "Understanding Solid Queue internals", clipping.title_for("en-US")
    assert_equal "Resumo.", clipping.summary_for("pt-BR")
  end

  test "can exist without a feed entry" do
    clipping = build_clipping

    assert clipping.valid?
    assert clipping.manual?
    assert_nil clipping.entry_id
  end

  test "a clipping from a feed is not manual" do
    assert_not clippings(:queued).manual?
  end

  test "display_source is the feed title for a feed clipping" do
    assert_equal clippings(:queued).entry.feed.display_title, clippings(:queued).display_source
  end

  test "display_source is the stored source name for a manual clipping" do
    clipping = build_clipping(source_name: "example.com")

    assert_equal "example.com", clipping.display_source
  end

  test "display_source is nil for a manual clipping without a source" do
    assert_nil build_clipping.display_source
  end

  test "display_title is the primary edition's title" do
    assert_equal "Rails 8.1 ships with a new queue UI", clippings(:queued).display_title
  end

  test "summary_source falls back to the entry summary when no text is stored" do
    assert_equal entries(:rails_eight).summary, clippings(:queued).summary_source
  end

  test "summary_source prefers the stored article text over the entry summary" do
    clipping = clippings(:queued)
    clipping.source_text = "texto completo do artigo"

    assert_equal "texto completo do artigo", clipping.summary_source
  end

  test "summary_source uses the stored article text when there is no entry" do
    clipping = build_clipping(source_text: "texto colado à mão")

    assert_equal "texto colado à mão", clipping.summary_source
  end

  test "a manual clipping cannot duplicate a queued URL" do
    existing = clippings(:queued)

    duplicate = build_clipping
    duplicate.variants.first.url = existing.variant_for("en-US").url

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :base
  end

  test "the manual URL check matches any edition's URL" do
    existing = clippings(:queued)

    duplicate = build_clipping
    duplicate.variants.first.url = existing.variant_for("pt-BR").url

    assert_not duplicate.valid?
  end

  test "the manual URL check ignores case" do
    existing = clippings(:queued)

    duplicate = build_clipping
    duplicate.variants.first.url = existing.variant_for("en-US").url.sub("rails-8-1", "RAILS-8-1")

    assert_not duplicate.valid?
  end

  test "the manual URL check only guards unsent clippings" do
    sent = clippings(:sent)

    clipping = build_clipping
    clipping.variants.first.url = sent.variant_for("en-US").url

    assert clipping.valid?
  end

  test "shippable leaves failed clippings out of the next issue" do
    clippings(:pending).update!(summary_status: :failed)

    assert_includes Clipping.shippable, clippings(:queued)
    assert_not_includes Clipping.shippable, clippings(:pending)
    assert_not_includes Clipping.shippable, clippings(:sent)
  end

  test "a clipping created as failed does not kick off a generation run" do
    assert_no_enqueued_jobs(only: GenerateSummaryJob) do
      build_clipping(summary_status: :failed, summary_error: "sem fonte").save!
    end
  end
end
