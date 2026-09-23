# Fetches an article page and pulls out the two things a manual clipping needs:
# a title, and the body text the summary is generated from.
#
# The HTML comes from a third-party site, so it is reduced to plain text here and
# never rendered anywhere.
class ArticleFetcher
  Error = Class.new(StandardError)

  # Bound on what we keep as the generation source. SummaryGenerator allows as
  # many characters, so the whole stored article reaches the model.
  MAX_TEXT_CHARS = 20_000

  # Never part of an article's text.
  NOISE_SELECTORS = "script, style, noscript, nav, header, footer, aside, form, iframe, svg, figcaption"

  # Reader discussion is not the article, yet comment sections often sit inside
  # the same <article>/<main> container. When they leak into the text, the model
  # reads a commenter's name and profile as the article's author, so they are
  # dropped before extraction. Covers the common comment containers (WordPress,
  # Disqus, dev.to).
  COMMENT_SELECTORS = "#comments, #comments-container, .comments, .comment-list, " \
                      "#disqus_thread, [id^='comment-node-']"

  Result = Struct.new(:title, :text, keyword_init: true)

  def initialize(transport: HttpTransport.default)
    @transport = transport
  end

  attr_reader :transport

  def call(url)
    html = transport.get(url, accept: HttpTransport::HTML_ACCEPT)
    document = Nokogiri::HTML(html)

    Result.new(title: extract_title(document, url), text: extract_text(document))
  rescue HttpTransport::Error => e
    raise Error, e.message
  end

  private

  # In order of trustworthiness: what the site says the title is, then the
  # document title, then the first heading, and finally the host as a fallback.
  def extract_title(document, url)
    candidates = [
      document.at_css('meta[property="og:title"]')&.[]("content"),
      document.at_css('meta[name="twitter:title"]')&.[]("content"),
      document.at_css("title")&.text,
      document.at_css("h1")&.text
    ]

    candidates.filter_map { |candidate| plain_text(candidate) }.first.presence ||
      URI.parse(url.to_s).host.to_s
  end

  def extract_text(document)
    document.css("#{NOISE_SELECTORS}, #{COMMENT_SELECTORS}").remove

    container = document.at_css("article") || document.at_css("main") || document.at_css("body")
    plain_text(container&.text).to_s[0, MAX_TEXT_CHARS]
  end

  # HTML entities are already decoded by the parser, so this only has to collapse
  # the whitespace a page is full of (`[[:space:]]` covers non-breaking spaces).
  def plain_text(value)
    return nil if value.nil?

    value.to_s.gsub(/[[:space:]]+/, " ").strip.presence
  end
end
