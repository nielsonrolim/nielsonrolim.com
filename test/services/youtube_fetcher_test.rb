require "test_helper"

class YoutubeFetcherTest < ActiveSupport::TestCase
  setup do
    @html = file_fixture("youtube_watch_page.html").read
    @captions = file_fixture("youtube_captions.json").read
  end

  # Builds a fetcher whose transport serves the watch page, then the caption
  # track (unless `captions:` says otherwise), recording every URL requested.
  #
  # `captions:` controls the single-track case: a String body, `:error` to fail
  # the request, or "" for an empty body. `caption_bodies:` drives the
  # multi-track case as an Array replayed in the order tracks are attempted,
  # where each entry is a body or `:error`.
  def fetcher(page: @html, captions: nil, caption_bodies: nil)
    @requested = []
    replies = caption_bodies&.dup
    session = lambda do |uri|
      @requested << uri.to_s
      if uri.to_s.include?("/api/timedtext")
        reply = caption_bodies ? replies.shift : captions
        if reply == :error
          raise HttpTransport::Error, "captions unavailable"
        else
          http_response(200, reply.to_s)
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

  test "asks for the caption track with a browser user agent and its language" do
    requests = []
    transport = HttpTransport.new(
      sender: lambda do |request, &block|
        requests << request
        body = request.path.include?("/api/timedtext") ? @captions : @html
        block.call(streaming_response(200, body))
      end
    )

    YoutubeFetcher.new(transport: transport).call("https://www.youtube.com/watch?v=xG-xACzIJQU")

    caption = requests.find { |request| request.path.include?("/api/timedtext") }
    assert_equal HttpTransport::BROWSER_USER_AGENT, caption["User-Agent"]
    assert_equal "pt", caption["Accept-Language"]
    # The watch page itself keeps the site's own user agent.
    watch = requests.find { |request| !request.path.include?("/api/timedtext") }
    assert_equal HttpTransport::USER_AGENT, watch["User-Agent"]
  end

  test "drops a malformed track language instead of sending it" do
    page = <<~HTML
      <html><head><meta property="og:title" content="t"></head><body>
      <script>var ytInitialPlayerResponse = {"shortDescription":"d","captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=pt","languageCode":"pt\\r\\nInjected: 1"}
      ]}}};</script></body></html>
    HTML

    requests = []
    transport = HttpTransport.new(
      sender: lambda do |request, &block|
        requests << request
        body = request.path.include?("/api/timedtext") ? @captions : page
        block.call(streaming_response(200, body))
      end
    )

    result = YoutubeFetcher.new(transport: transport).call("https://www.youtube.com/watch?v=a")

    caption = requests.find { |request| request.path.include?("/api/timedtext") }
    assert_nil caption["Accept-Language"]
    assert_includes result.text, "hoje vamos falar sobre o Jev"
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

  # --- Multiple caption tracks ------------------------------------------------

  setup do
    @multi = file_fixture("youtube_watch_page_multiple_tracks.html").read
    @second = file_fixture("youtube_captions_second.json").read
  end

  test "prefers the original language's human track" do
    # pt is the original (defaultAudioTrackIndex points at the pt audio): the
    # pt human track is chosen even though it is listed last.
    result = fetcher(page: @multi, caption_bodies: [ @captions ]).call("https://www.youtube.com/watch?v=abc123")

    assert_includes result.text, "hoje vamos falar sobre o Jev"
    refute_includes result.text, "Segunda faixa"
  end

  test "falls back to the next track when the first fails" do
    result = fetcher(page: @multi, caption_bodies: [ :error, @second ]).call("https://www.youtube.com/watch?v=abc123")

    assert_includes result.text, "Segunda faixa"
  end

  test "falls back to the next track when the first is empty" do
    result = fetcher(page: @multi, caption_bodies: [ '{"events":[]}', @second ]).call("https://www.youtube.com/watch?v=abc123")

    assert_includes result.text, "Segunda faixa"
  end

  test "prefers the auto-generated track over a human one in the same language" do
    page = <<~HTML
      <html><head><meta property="og:title" content="t"></head><body>
      <script>var ytInitialPlayerResponse = {"shortDescription":"d","captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=en","languageCode":"en","vssId":".en"},
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=en\\u0026caps=asr","languageCode":"en","vssId":"a.en","kind":"asr"}
      ]}}};</script></body></html>
    HTML

    fetcher(page: page, caption_bodies: [ @second ]).call("https://www.youtube.com/watch?v=a")

    # Same language, so the auto-generated track is ranked ahead of the human
    # one even though the human one is listed first in the page.
    assert_includes @requested.find { |url| url.include?("/api/timedtext") }, "caps=asr"
  end

  test "prefers an original-language auto track over a human track in another language" do
    page = <<~HTML
      <html><head><meta property="og:title" content="t"></head><body>
      <script>var ytInitialPlayerResponse = {"shortDescription":"d","defaultAudioLanguage":"en","captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=pt","languageCode":"pt","vssId":".pt"},
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=en\\u0026caps=asr","languageCode":"en","vssId":"a.en","kind":"asr"}
      ]}}};</script></body></html>
    HTML

    fetcher(page: page, caption_bodies: [ @second ]).call("https://www.youtube.com/watch?v=a")

    # en is the original language, so its auto track is tried before the pt one.
    assert_includes @requested.find { |url| url.include?("/api/timedtext") }, "lang=en"
  end

  test "stops after the first successful track" do
    fetcher(page: @multi, caption_bodies: [ @captions, :error ]).call("https://www.youtube.com/watch?v=abc123")

    assert_equal 1, @requested.count { |url| url.include?("/api/timedtext") }
  end

  test "tries at most MAX_TRACK_ATTEMPTS tracks" do
    fetcher(page: @multi, caption_bodies: [ :error, :error, :error, @second ]).call("https://www.youtube.com/watch?v=abc123")

    assert_equal YoutubeFetcher::MAX_TRACK_ATTEMPTS, @requested.count { |url| url.include?("/api/timedtext") }
  end

  test "reads the original language from defaultAudioLanguage when present" do
    page = <<~HTML
      <html><head><meta property="og:title" content="t"></head><body>
      <script>var ytInitialPlayerResponse = {"shortDescription":"d","defaultAudioLanguage":"pt-BR","captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=en","languageCode":"en"},
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=pt","languageCode":"pt"}
      ]}}};</script></body></html>
    HTML

    result = fetcher(page: page, caption_bodies: [ @second ]).call("https://www.youtube.com/watch?v=a")

    # The pt track is attempted first, so the en one is never requested.
    assert_equal 1, @requested.count { |url| url.include?("/api/timedtext") }
    assert_includes @requested.find { |url| url.include?("/api/timedtext") }, "lang=pt"
    assert_includes result.text, "Segunda faixa"
  end

  # --- The transcript budget --------------------------------------------------

  test "leaves a short transcript whole, without a truncation marker" do
    result = fetcher(page: @multi, caption_bodies: [ @captions ]).call("https://www.youtube.com/watch?v=abc123")

    refute_includes result.text, YoutubeFetcher::TRANSCRIPT_GAP
    assert_operator result.text.length, :<=, YoutubeFetcher::MAX_TEXT_CHARS
  end

  test "cuts a long transcript at head and tail, keeping the conclusion" do
    transcript = ("A" * 30_000) + "MEIO-MARCADOR" + ("B" * 30_000)
    captions = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => transcript } ] } ] })

    result = fetcher(page: @multi, caption_bodies: [ captions ]).call("https://www.youtube.com/watch?v=abc123")

    assert_operator result.text.length, :<=, YoutubeFetcher::MAX_TEXT_CHARS
    assert_includes result.text, "A" * 100
    assert_includes result.text, "B" * 100
    assert_includes result.text, YoutubeFetcher::TRANSCRIPT_GAP
    refute_includes result.text, "MEIO-MARCADOR"
  end

  test "leaves the transcript out when the description fills the budget" do
    description = "D" * (YoutubeFetcher::MAX_TEXT_CHARS + 500)
    page = <<~HTML
      <html><head><meta property="og:title" content="t"></head><body>
      <script>var ytInitialPlayerResponse = {"shortDescription":"#{description}","captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
        {"baseUrl":"https://www.youtube.com/api/timedtext?v=a\\u0026lang=pt","languageCode":"pt"}
      ]}}};</script></body></html>
    HTML

    result = fetcher(page: page, caption_bodies: [ @captions ]).call("https://www.youtube.com/watch?v=a")

    assert_operator result.text.length, :<=, YoutubeFetcher::MAX_TEXT_CHARS
    refute_includes result.text, YoutubeFetcher::TRANSCRIPT_GAP
    refute_includes result.text, "hoje vamos falar"
  end

  test "keeps the YouTube ceiling equal to the article and generator ceilings" do
    assert_equal ArticleFetcher::MAX_TEXT_CHARS, YoutubeFetcher::MAX_TEXT_CHARS
    assert_equal SummaryGenerator::MAX_SOURCE_CHARS, YoutubeFetcher::MAX_TEXT_CHARS
  end
end
