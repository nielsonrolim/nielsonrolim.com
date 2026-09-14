require "cgi"
require "json"

# Where a manual clipping comes from, derived from its URL at creation time:
# the channel name for a YouTube video, the site domain for anything else.
#
# The domain needs no HTTP, so it is filled in even when the article fetch
# fails. The channel name comes from YouTube's oEmbed endpoint — no API key —
# and falls back to the host when that cannot be reached.
class SourceNameResolver
  OEMBED_ENDPOINT = "https://www.youtube.com/oembed"
  JSON_ACCEPT = "application/json"

  def initialize(transport: HttpTransport.default)
    @transport = transport
  end

  attr_reader :transport

  def call(url)
    host = host_of(url)
    return if host.blank?

    if youtube?(host)
      channel_name(url) || host
    else
      host.sub(/\Awww\./, "")
    end
  end

  private

  def youtube?(host)
    host == "youtu.be" || host == "youtube.com" || host.end_with?(".youtube.com")
  end

  def channel_name(url)
    response = transport.get("#{OEMBED_ENDPOINT}?url=#{CGI.escape(url)}&format=json", accept: JSON_ACCEPT)
    JSON.parse(response)["author_name"].presence
  rescue HttpTransport::Error, JSON::ParserError
    nil
  end

  def host_of(url)
    URI.parse(url.to_s).host.to_s.downcase
  rescue URI::InvalidURIError
    ""
  end
end
