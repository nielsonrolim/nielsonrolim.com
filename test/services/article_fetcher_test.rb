require "test_helper"

class ArticleFetcherTest < ActiveSupport::TestCase
  # Records the `accept:` it was asked for, which the real transport uses to
  # build the request and a canned session cannot observe.
  class RecordingTransport
    attr_reader :accepts

    def initialize(body)
      @body = body
      @accepts = []
    end

    def get(url, accept: nil, **)
      @accepts << accept
      @body
    end
  end

  setup do
    @html = file_fixture("article.html").read
  end

  def fetch(html, url: "https://example.com/post")
    ArticleFetcher.new(transport: transport_always(http_response(200, html))).call(url)
  end

  test "prefers the og:title" do
    assert_equal "Rails ships a new queue UI", fetch(@html).title
  end

  test "falls back to the document title" do
    html = @html.sub(/<meta property="og:title"[^>]*>/, "")

    assert_equal "Fallback title | Example News", fetch(html).title
  end

  test "falls back to the first heading" do
    html = @html.sub(/<meta property="og:title"[^>]*>/, "").sub(%r{<title>.*?</title>}m, "")

    assert_equal "Rails ships a new queue UI", fetch(html).title
  end

  test "falls back to the host when the page declares no title" do
    html = "<html><body><p>Just some text.</p></body></html>"

    assert_equal "example.com", fetch(html, url: "https://example.com/a/b").title
  end

  test "extracts the article text" do
    text = fetch(@html).text

    assert_includes text, "Solid Queue replaces Redis with a database-backed adapter."
    assert_includes text, "recurring tasks, concurrency controls"
  end

  test "leaves out scripts, styles, chrome and asides" do
    text = fetch(@html).text

    assert_not_includes text, "should not appear"
    assert_not_includes text, "color: #b01e2d"
    assert_not_includes text, "Home"
    assert_not_includes text, "About"
    assert_not_includes text, "Related"
    assert_not_includes text, "Example News"
  end

  test "leaves out reader comments" do
    text = fetch(@html).text

    assert_not_includes text, "Great post!"
    assert_not_includes text, "Jane Commenter"
  end

  test "collapses non-breaking spaces and line breaks into single spaces" do
    text = fetch(@html).text

    assert_includes text, "Solid Queue replaces Redis"
    assert_not_includes text, "\u00A0"
    assert_not_includes text, "\n"
  end

  test "truncates an enormous page" do
    huge = "<html><body><article><p>#{'palavra ' * 10_000}</p></article></body></html>"

    assert_equal ArticleFetcher::MAX_TEXT_CHARS, fetch(huge).text.length
  end

  test "asks for HTML" do
    transport = RecordingTransport.new(@html)

    ArticleFetcher.new(transport: transport).call("https://example.com/post")

    assert_equal [ HttpTransport::HTML_ACCEPT ], transport.accepts
  end

  test "raises its own error when the transport fails" do
    transport = transport_always(http_response(404, "gone"))

    error = assert_raises(ArticleFetcher::Error) do
      ArticleFetcher.new(transport: transport).call("https://example.com/post")
    end

    assert_match(/HTTP 404/, error.message)
  end

  test "raises when the URL is not fetchable" do
    transport = transport_always(http_response(200, @html))

    assert_raises(ArticleFetcher::Error) do
      ArticleFetcher.new(transport: transport).call("file:///etc/passwd")
    end
  end
end
