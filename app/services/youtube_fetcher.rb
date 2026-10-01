require "json"

# Fetches a YouTube video's own content: the title, the full description and,
# when YouTube offers one, the caption transcript.
#
# A watch page is a JavaScript app. Its static HTML has no article text at all,
# only chrome (a copyright footer), which is why the generic ArticleFetcher
# extraction was useless there: the model received a page footer and summarized
# the absence of content. The video's data does travel in the page, though, in
# `ytInitialPlayerResponse`, so this reads that directly.
#
# The transcript is best effort. YouTube serves captions from a signed URL that
# can be unavailable (region, bot checks, expired signature), so a failed or
# empty response falls back to the description alone instead of failing the
# fetch.
class YoutubeFetcher
  Error = Class.new(StandardError)

  WATCH_ENDPOINT = "https://www.youtube.com/watch"
  JSON_ACCEPT = "application/json"

  # Path prefixes that carry the video id in the segment right after them.
  ID_PREFIXES = %w[shorts embed live v].freeze

  # The full description lives inside the player response JSON embedded in the
  # page. Pulling the one string out, rather than parsing the whole blob, keeps
  # this robust against the rest of that object changing shape.
  SHORT_DESCRIPTION = /"shortDescription":"((?:[^"\\]|\\.)*)"/m

  # The first caption track's URL, stored as a JSON-escaped string.
  CAPTION_TRACK = /"baseUrl":"(https:\/\/www\.youtube\.com\/api\/timedtext[^"]*)"/m

  Result = Struct.new(:title, :text, keyword_init: true)

  # The video id in `url`, or nil when it is not a YouTube video URL. Covers
  # watch links, youtu.be short links and the /shorts, /embed, /live and /v
  # paths, on youtube.com and its subdomains.
  def self.video_id(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.is_a?(URI::HTTP)

    host = uri.host.to_s.downcase
    if host == "youtu.be"
      first_segment(uri)
    elsif host == "youtube.com" || host.end_with?(".youtube.com")
      segments = uri.path.to_s.split("/").reject(&:empty?)

      if segments.first == "watch"
        query_value(uri, "v")
      elsif ID_PREFIXES.include?(segments.first)
        segments[1].presence
      end
    end
  rescue URI::InvalidURIError
    nil
  end

  def self.first_segment(uri)
    uri.path.to_s.split("/").reject(&:empty?).first.presence
  end
  private_class_method :first_segment

  def self.query_value(uri, key)
    URI.decode_www_form(uri.query.to_s).to_h[key].presence
  rescue ArgumentError
    nil
  end
  private_class_method :query_value

  def initialize(transport: HttpTransport.default)
    @transport = transport
  end

  attr_reader :transport

  def call(url)
    id = self.class.video_id(url)
    raise Error, "not a YouTube video URL: #{url}" if id.blank?

    html = transport.get("#{WATCH_ENDPOINT}?v=#{id}", accept: HttpTransport::HTML_ACCEPT)
    description = description_from(html)
    raise Error, "no description found for YouTube video #{id}" if description.blank?

    title = title_from(html).presence || "YouTube video #{id}"
    Result.new(title: title, text: compose(description, transcript_from(html)))
  rescue HttpTransport::Error => e
    raise Error, e.message
  end

  private

  # Prefer the player response: the <meta> description is truncated to about
  # 160 characters, while `shortDescription` holds the whole thing.
  def description_from(html)
    from_short_description(html).presence || meta_content(html, "og:description")
  end

  def from_short_description(html)
    match = html[SHORT_DESCRIPTION, 1]
    return nil if match.blank?

    JSON.parse(%("#{match}"))
  rescue JSON::ParserError
    nil
  end

  def title_from(html)
    meta_content(html, "og:title")
  end

  def meta_content(html, property)
    document = Nokogiri::HTML(html)
    document.at_css(%(meta[property="#{property}"]))&.[]("content").presence ||
      document.at_css(%(meta[name="#{property}"]))&.[]("content").presence
  end

  # The caption track is a signed URL; `&fmt=json3` asks for the segment JSON
  # rather than the default XML. A transport error, an empty body or a shape
  # change all just mean "no transcript", never a failed fetch.
  def transcript_from(html)
    url = html[CAPTION_TRACK, 1]
    return if url.blank?

    body = transport.get(unescape(url) + "&fmt=json3", accept: JSON_ACCEPT)
    events = JSON.parse(body)["events"]
    return if events.blank?

    text = Array(events).flat_map { |event| Array(event["segs"]).map { |seg| seg["utf8"] } }.join
    text.gsub(/[[:space:]]+/, " ").strip.presence
  rescue HttpTransport::Error, JSON::ParserError, TypeError
    nil
  end

  # The caption URL is embedded as a JSON string, so `&` arrives as `\u0026`.
  def unescape(value)
    JSON.parse(%("#{value}"))
  rescue JSON::ParserError
    value
  end

  def compose(description, transcript)
    return description if transcript.blank?

    "#{description}\n\n#{transcript}"
  end
end
