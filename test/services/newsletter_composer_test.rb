require "test_helper"

class NewsletterComposerTest < ActiveSupport::TestCase
  setup do
    @clippings = [ clippings(:queued), clippings(:sent) ]
    @date = Time.utc(2026, 9, 14, 9, 0, 0)
  end

  test "renders the pt-BR title, summary, link, source and language as HTML" do
    html = NewsletterComposer.new(@clippings, date: @date).to_html

    assert_includes html, "O Rails 8.1 traz uma nova interface de filas"
    assert_includes html, "https://example.com/rails-8-1"
    assert_includes html, "O Rails 8.1 traz um novo painel de filas."
    assert_includes html, "Ruby Weekly"
    assert_includes html, "en-US"
  end

  test "renders the en-US title and summary when composing in English" do
    html = NewsletterComposer.new(@clippings, date: @date, locale: :"en-US").to_html

    assert_includes html, "Rails 8.1 ships with a new queue UI"
    assert_includes html, "Solid Queue is a database-backed adapter for Active Job."
    assert_not_includes html, "O Rails 8.1 traz uma nova interface de filas"
  end

  test "renders a plain-text twin without markup" do
    text = NewsletterComposer.new(@clippings, date: @date).to_text

    assert_includes text, "O Rails 8.1 traz uma nova interface de filas"
    assert_includes text, "https://example.com/rails-8-1"
    assert_includes text, "fonte: Ruby Weekly"
    assert_includes text, "idiomas: pt-BR, en-US"
    assert_not_includes text, "<table"
  end

  test "renders the stored source of a manual clipping" do
    clipping = Clipping.new(source_name: "example.org", summary_status: "summarized")
    clipping.variants.build(url: "https://example.org/post", title: "Adicionado à mão", summary: "Resumo.")
    clipping.save!

    composer = NewsletterComposer.new([ clipping ], date: @date)

    assert_includes composer.to_html, ". example.org"
    assert_includes composer.to_text, "fonte: example.org"
  end

  test "links each language to its own edition" do
    clipping = clippings(:queued)
    clipping.variant_for("pt-BR").update!(url: "https://example.com/rails-8-1-pt")

    assert_includes NewsletterComposer.new([ clipping ], date: @date).to_html, "https://example.com/rails-8-1-pt"
    assert_includes NewsletterComposer.new([ clipping ], date: @date, locale: :"en-US").to_html, "https://example.com/rails-8-1"
  end

  test "sends the translated text and the source link for a one-language story" do
    clipping = clippings(:single) # en-US article, pt-BR translation with no URL

    html = NewsletterComposer.new([ clipping ], date: @date).to_html

    assert_includes html, "Uma história em um idioma só"
    assert_includes html, "Resumo em português."
    assert_includes html, "https://example.com/single"
  end

  test "links each reader to their edition, falling back when the story has none" do
    bilingual = clippings(:queued) # published in en-US and pt-BR
    bilingual.variant_for("pt-BR").update!(url: "https://example.com/rails-8-1-pt")

    # Published in pt-BR only: the en-US variant is just a translation.
    single = Clipping.new(source_name: "diolinux.com.br")
    single.variants.build(locale: "pt-BR", url: "https://diolinux.com.br/post",
                          title: "Até a Epic!", summary: "Resumo em português.")
    single.variants.build(locale: "en-US", title: "Even Epic!", summary: "Summary in English.")

    clippings = [ bilingual, single ]
    english = NewsletterComposer.new(clippings, date: @date, locale: :"en-US").to_html
    portuguese = NewsletterComposer.new(clippings, date: @date).to_html

    # Bilingual story: en-US goes to the en-US edition, pt-BR to the pt-BR one.
    assert_includes english, "https://example.com/rails-8-1"
    assert_not_includes english, "https://example.com/rails-8-1-pt"
    assert_includes portuguese, "https://example.com/rails-8-1-pt"

    # pt-BR-only story: both languages point at the pt-BR edition.
    assert_includes english, "https://diolinux.com.br/post"
    assert_includes english, "Even Epic!"
    assert_includes portuguese, "https://diolinux.com.br/post"
    assert_includes portuguese, "Até a Epic!"
  end

  test "the plain-text header uses the composer's language" do
    assert_includes NewsletterComposer.new(@clippings, date: @date, locale: :"en-US").to_text,
                    "Tech clipping — 2026-09-14"
  end

  test "numbers the clippings in order" do
    html = NewsletterComposer.new(@clippings, date: @date).to_html

    assert_includes html, "01."
    assert_includes html, "02."
  end

  test "escapes markup smuggled in through a feed, in both languages" do
    clipping = clippings(:queued)
    clipping.variant_for("en-US").update_columns(
      title: "(script)alert(1)(/script)", summary: "<b>bold</b> & \"quoted\""
    )
    clipping.variant_for("pt-BR").update_columns(
      title: "(script)alert(2)(/script)", summary: "<i>it</i> & \"aspas\""
    )

    html = NewsletterComposer.new([ clipping ], date: @date).to_html

    assert_includes html, "&amp;"
    assert_includes html, "&quot;"
    # Neither the original nor the translation is taken as markup.
    assert_not_includes html, "<b>bold</b>"
    assert_not_includes html, "<i>it</i>"
  end

  test "renders a clipping that has not been summarized yet" do
    clipping = clippings(:pending)
    assert_nil clipping.summary_for("pt-BR")
    assert_nil clipping.source_variant.locale

    composer = NewsletterComposer.new([ clipping ], date: @date)

    # With no detected language, both languages show the source edition.
    assert_includes composer.to_html, clipping.display_title
    assert_includes composer.to_html, clipping.url_for("pt-BR")
    assert_match(/1 link selecionado/, composer.to_html)
    assert_includes composer.to_text, clipping.display_title
  end

  test "renders an empty state" do
    composer = NewsletterComposer.new([], date: @date)
    empty_copy = I18n.t("newsletters.email.empty")

    assert composer.empty?
    assert_includes composer.to_html, empty_copy
    assert_includes composer.to_text, empty_copy
  end

  test "builds a localized subject with the issue date" do
    assert_equal "Clipping de tecnologia — 14/09/2026",
                 NewsletterComposer.new(@clippings, date: @date).subject
  end

  test "honours an explicit locale" do
    composer = NewsletterComposer.new(@clippings, date: @date, locale: :"en-US")

    assert_equal "Tech clipping — 2026-09-14", composer.subject
    assert_includes composer.to_html, "Worth reading this week"
  end

  test "states how many links the issue carries" do
    html = NewsletterComposer.new(@clippings, date: @date).to_html

    assert_match(/2 links selecionados/, html)
  end
end
