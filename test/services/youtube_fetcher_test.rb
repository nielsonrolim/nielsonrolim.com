require "test_helper"

class YoutubeFetcherTest < ActiveSupport::TestCase
  setup do
    @html = file_fixture("youtube_watch_page.html").read
    @captions = file_fixture("youtube_captions.json").read
  end

  # Builds a fetcher whose transport serves the watch page, then the caption
  # track (unless `captions:` says otherwise), recording every URL requested.
  def fetcher(page: @html, captions: nil)
    @requested = []
    session = lambda do |uri|
      @requested << uri.to_s
      if uri.to_s.include?("/api/timedtext")
        if captions.is_a?(Symbol)
          raise HttpTransport::Error, "captions unavailable"
        else
          http_response(200, captions.to_s)
        end
      else
        http_response(200, page)
      end
    end

    YoutubeFetcher.new(transport: HttpTransport.new(session: session))
  end

  test "extracts the title and the full description" do
    result = fetcher.call("https://www.youtube.com/watch?v=xG-xACzIJQU")

    assert_equal "Jev: O Novo Hype da IA para Devs (QUE NÃO É HYPE)", result.title
    assert_includes result.text, "Conheça o Jev, o novo modelo de IA da TypeSafe AI"
    # The chrome that broke the generic extraction must never leak in.
    assert_not_includes result.text, "AboutPressCopyright"
  end

  test "requests the watch page for the video id" do
    fetcher.call("https://youtu.be/xG-xACzIJQU")

    assert_equal "https://www.youtube.com/watch?v=xG-xACzIJQU", @requested.first
  end

  test "appends the transcript when captions are available" do
    result = fetcher(captions: @captions).call("https://www.youtube.com/watch?v=xG-xACzIJQU")

    assert_includes result.text, "hoje vamos falar sobre o Jev"
    assert_includes result.text, "O Jev é um runtime de IA para agentes"
    # The description stays in front of the transcript.
    assert_operator result.text.index("Conheça o Jev"), :<, result.text.index("hoje vamos falar")
  end

  test "falls back to the description when the caption request fails" do
    result = fetcher(captions: :error).call("https://www.youtube.com/watch?v=xG-xACzIJQU")

    assert_includes result.text, "Conheça o Jev"
    assert_not_includes result.text, "hoje vamos falar"
  end

  test "falls back to the description when the caption body is empty" do
    result = fetcher(captions: "").call("https://www.youtube.com/watch?v=xG-xACzIJQU")

    assert_includes result.text, "Conheça o Jev"
  end

  test "falls back to the truncated meta description when the player data is absent" do
    page = <<~HTML
      <html><head>
        <meta property="og:title" content="Sem player">
        <meta property="og:description" content="Descrição curta vinda da meta tag.">
      </head><body>chrome</body></html>
    HTML

    result = fetcher(page: page).call("https://www.youtube.com/watch?v=abc123")

    assert_equal "Sem player", result.title
    assert_equal "Descrição curta vinda da meta tag.", result.text
  end

  test "raises when the page carries no description at all" do
    page = "<html><head><title>Sem descrição</title></head><body>chrome</body></html>"

    error = assert_raises(YoutubeFetcher::Error) do
      fetcher(page: page).call("https://www.youtube.com/watch?v=abc123")
    end

    assert_match(/no description/, error.message)
  end

  test "rejects a URL that is not a YouTube video" do
    assert_raises(YoutubeFetcher::Error) do
      fetcher.call("https://example.com/post")
    end
  end

  test "reads the video id from every link shape" do
    {
      "https://www.youtube.com/watch?v=abc123&t=30" => "abc123",
      "https://youtu.be/abc123?si=xyz" => "abc123",
      "https://www.youtube.com/shorts/abc123" => "abc123",
      "https://www.youtube.com/embed/abc123" => "abc123",
      "https://www.youtube.com/live/abc123" => "abc123",
      "https://m.youtube.com/watch?v=abc123" => "abc123",
      "https://music.youtube.com/watch?v=abc123" => "abc123"
    }.each do |url, id|
      assert_equal id, YoutubeFetcher.video_id(url), "expected #{id} from #{url}"
    end
  end

  test "ignores a YouTube URL that is not a video" do
    assert_nil YoutubeFetcher.video_id("https://www.youtube.com/@codigofontextv")
    assert_nil YoutubeFetcher.video_id("https://www.youtube.com/feed/subscriptions")
    assert_nil YoutubeFetcher.video_id("https://example.com/watch?v=abc123")
    assert_nil YoutubeFetcher.video_id("file:///etc/passwd")
    assert_nil YoutubeFetcher.video_id("not a url")
  end
end
