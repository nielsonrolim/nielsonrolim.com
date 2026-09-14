require "test_helper"

class SourceNameResolverTest < ActiveSupport::TestCase
  def resolve(url, transport: transport_always(http_response(200, "unused")))
    SourceNameResolver.new(transport: transport).call(url)
  end

  test "a news site resolves to its domain" do
    assert_equal "example.com", resolve("https://example.com/path/to/news")
  end

  test "strips a leading www from the domain" do
    assert_equal "example.com", resolve("https://www.example.com/news")
  end

  test "a YouTube video resolves to the channel name" do
    oembed = JSON.generate("author_name" => "Canal Exemplo", "title" => "Um vídeo")
    transport = transport_always(http_response(200, oembed))

    assert_equal "Canal Exemplo", resolve("https://www.youtube.com/watch?v=abc123", transport: transport)
    assert_equal "Canal Exemplo", resolve("https://youtu.be/abc123", transport: transport)
  end

  test "falls back to the host when the oEmbed call fails" do
    transport = transport_always(http_response(404, "not found"))

    assert_equal "www.youtube.com", resolve("https://www.youtube.com/watch?v=abc123", transport: transport)
  end

  test "falls back to the host when the oEmbed response is not JSON" do
    transport = transport_always(http_response(200, "<html></html>"))

    assert_equal "youtu.be", resolve("https://youtu.be/abc123", transport: transport)
  end

  test "an invalid URL has no source" do
    assert_nil resolve("not-a-url")
  end
end
