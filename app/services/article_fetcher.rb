# Fetches an article page and pulls out the two things a manual clipping needs:
# a title, and the body text the summary is generated from.
#
# The HTML comes from a third-party site, so it is reduced to plain text here and
# never rendered anywhere.
#
# A YouTube watch page needs its own extraction (its content is rendered by
# JavaScript), so those URLs are delegated to YoutubeFetcher.
class ArticleFetcher
  Error = Class.new(StandardError)

  # Bound on what we keep as the generation source. SummaryGenerator allows as
  # many characters, so the whole stored article reaches the model, and the two
  # must stay equal — a lower ceiling here would clip an article this already
  # fetched, and a higher one would store text the summary never sees.
  #
  # Sized against real articles rather than a round guess: a 31k-character
  # technical post was being cut at 20k, mid-sentence and mid-section, losing
  # the conclusion — and the conclusion is what the prompt asks the summary to
  # open on. 40k covers that whole with headroom and still leaves the models
  # (and the 180s timeout) comfortable. Past this, longer input starts costing
  # latency and diluting the middle rather than improving the summary.
  MAX_TEXT_CHARS = 40_000

  # Never part of an article's text.
  NOISE_SELECTORS = "script, style, noscript, nav, header, footer, aside, form, iframe, svg, figcaption"

  # Reader discussion is not the article, yet comment sections often sit inside
  # the same <article>/<main> container. When they leak into the text, the model
  # reads a commenter's name and profile as the article's author, so they are
  # dropped before extraction. Covers the common comment containers (WordPress,
  # Disqus, dev.to).
  COMMENT_SELECTORS = "#comments, #comments-container, .comments, .comment-list, " \
                      "#disqus_thread, [id^='comment-node-']"

  # A page whose content is rendered by JavaScript leaves only its chrome in the
  # static HTML, and storing that makes the model summarize the absence of
  # content. YouTube watch pages have their own path (see YoutubeFetcher); this
  # catches the same failure elsewhere. A body that is nothing but known chrome
  # is reported as a failed fetch, so the caller falls back to the RSS excerpt.
  CHROME_PATTERNS = [
    /\AAboutPressCopyrightContact us/,
    /\AJavaScript is disabled/i
  ].freeze

  Result = Struct.new(:title, :text, keyword_init: true)

  def initialize(transport: HttpTransport.default)
    @transport = transport
  end

  attr_reader :transport

  def call(url)
    return fetch_youtube(url) if YoutubeFetcher.video_id(url)

    html = transport.get(url, accept: HttpTransport::HTML_ACCEPT)
    document = Nokogiri::HTML(html)

    Result.new(title: extract_title(document, url), text: extract_text(document))
  rescue HttpTransport::Error => e
    raise Error, e.message
  end

  private

  # The video fetcher reads the page's embedded player data instead of its
  # visible text, so it is handed the same transport and its result mapped onto
  # this class's Result shape.
  def fetch_youtube(url)
    video = YoutubeFetcher.new(transport: transport).call(url)
    Result.new(title: video.title, text: video.text)
  rescue YoutubeFetcher::Error => e
    raise Error, e.message
  end

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
    text = plain_text(container&.text).to_s[0, MAX_TEXT_CHARS]
    raise Error, "page body is only site chrome" if chrome_only?(text)

    text
  end

  def chrome_only?(text)
    text.present? && CHROME_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  # HTML entities are already decoded by the parser, so this only has to collapse
  # the whitespace a page is full of (`[[:space:]]` covers non-breaking spaces).
  def plain_text(value)
    return nil if value.nil?

    value.to_s.gsub(/[[:space:]]+/, " ").strip.presence
  end
end
