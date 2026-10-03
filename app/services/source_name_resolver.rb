require "cgi"
require "json"

# Where a manual clipping comes from, derived from its URL at creation time:
# the channel name for a YouTube video, the site domain for anything else, and —
# for a YouTube video — the video's own title, which the same oEmbed response
# carries.
#
# The domain needs no HTTP, so it is filled in even when the article fetch
# fails. The channel name and title come from YouTube's oEmbed endpoint — no API
# key — and fall back to the host (with no title) when that cannot be reached.
class SourceNameResolver
  OEMBED_ENDPOINT = "https://www.youtube.com/oembed"
  JSON_ACCEPT = "application/json"

  # `name` is the display source; `title` is the item's own title when the site
  # exposes one (YouTube), otherwise nil.
  Result = Struct.new(:name, :title, keyword_init: true)

  def initialize(transport: HttpTransport.default)
    @transport = transport
  end

  attr_reader :transport

  # The display source alone, kept for callers that only need it — the backfill
  # migration resolves a name per clipping and stores nothing else.
  def call(url)
    resolve(url)&.name
  end

  def resolve(url)
    host = host_of(url)
    return if host.blank?

    return Result.new(name: host.sub(/\Awww\./, "")) unless youtube?(host)

    metadata = oembed(url)
    Result.new(name: metadata["author_name"].presence || host, title: metadata["title"].presence)
  end

  private

  def youtube?(host)
    host == "youtu.be" || host == "youtube.com" || host.end_with?(".youtube.com")
  end

  # One request carries both the channel name and the video title.
  def oembed(url)
    response = transport.get("#{OEMBED_ENDPOINT}?url=#{CGI.escape(url)}&format=json", accept: JSON_ACCEPT)
    metadata = JSON.parse(response)
    metadata.is_a?(Hash) ? metadata : {}
  rescue HttpTransport::Error, JSON::ParserError
    {}
  end

  def host_of(url)
    URI.parse(url.to_s).host.to_s.downcase
  rescue URI::InvalidURIError
    ""
  end
end
