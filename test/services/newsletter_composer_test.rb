require "test_helper"

class NewsletterComposerTest < ActiveSupport::TestCase
  setup do
    @clippings = [ clippings(:queued), clippings(:sent) ]
    @date = Time.utc(2026, 9, 14, 9, 0, 0)
  end

  test "renders titles, links, summaries and the source feed as HTML" do
    html = NewsletterComposer.new(@clippings, date: @date).to_html

    assert_includes html, "Rails 8.1 ships with a new queue UI"
    assert_includes html, "https://example.com/rails-8-1"
    assert_includes html, "O Rails 8.1 traz um novo painel de filas."
    assert_includes html, "Ruby Weekly"
  end

  test "renders a plain-text twin without markup" do
    text = NewsletterComposer.new(@clippings, date: @date).to_text

    assert_includes text, "Rails 8.1 ships with a new queue UI"
    assert_includes text, "https://example.com/rails-8-1"
    assert_includes text, "fonte: Ruby Weekly"
    assert_not_includes text, "<table"
  end

  test "numbers the clippings in order" do
    html = NewsletterComposer.new(@clippings, date: @date).to_html

    assert_includes html, "01."
    assert_includes html, "02."
  end

  test "escapes markup smuggled in through a feed" do
    clipping = clippings(:queued)
    clipping.update_columns(title: %(<script>alert(1)</script>), summary: %(<b>bold</b> & "quoted"))

    html = NewsletterComposer.new([ clipping ], date: @date).to_html

    assert_not_includes html, "<script>"
    assert_includes html, "&lt;script&gt;"
    assert_not_includes html, "<b>bold</b>"
    assert_includes html, "&amp;"
  end

  test "renders a clipping that has no summary yet" do
    clipping = clippings(:pending)
    assert_nil clipping.summary

    composer = NewsletterComposer.new([ clipping ], date: @date)

    assert_includes composer.to_html, clipping.title
    assert_includes composer.to_html, clipping.url
    assert_match(/1 link selecionado/, composer.to_html)
    assert_includes composer.to_text, clipping.title
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
