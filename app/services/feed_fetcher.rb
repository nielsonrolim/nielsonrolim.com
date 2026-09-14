require "net/http"
require "zlib"
require "stringio"
require "cgi"

# Downloads a feed, parses it with Feedjira and stores the entries it has not
# seen before.
#
# Feedjira 4 no longer performs HTTP itself, so the transport (redirects, gzip,
# size caps, timeouts) lives in FeedFetcher::HttpTransport and is injectable,
# which keeps this class testable without touching the network.
class FeedFetcher
  Error = Class.new(StandardError)

  USER_AGENT = "nielsonrolim.com RSS reader (+https://nielsonrolim.com)"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 20
  MAX_REDIRECTS = 5
  MAX_BODY_BYTES = 5 * 1024 * 1024

  # How many entries a single poll will store for one feed.
  DEFAULT_ENTRY_LIMIT = 100

  Result = Struct.new(:feed, :new_entries, :error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  FULL_SANITIZER = Rails::HTML::FullSanitizer.new

  # The HTTP half of a fetch: follows redirects, inflates compressed bodies,
  # enforces a size cap and returns UTF-8 text.
  #
  # `session` performs one request for a URI and returns a Net::HTTPResponse.
  # It is injectable so tests can drive redirects and encodings without sockets.
  class HttpTransport
    def initialize(session: nil)
      @session = session
    end

    def get(url, redirects_left: MAX_REDIRECTS)
      raise Error, "too many redirects" if redirects_left.negative?

      uri = URI.parse(url.to_s)
      raise Error, "unsupported URL: #{url}" unless uri.is_a?(URI::HTTP) && uri.host.present?

      response = perform(uri)

      case response
      when Net::HTTPSuccess
        decode(response)
      when Net::HTTPRedirection
        location = response["location"]
        raise Error, "redirect without a Location header" if location.blank?

        get(URI.join(uri, location).to_s, redirects_left: redirects_left - 1)
      else
        raise Error, "HTTP #{response.code} for #{uri}"
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError,
           Net::OpenTimeout, Net::ReadTimeout, IOError, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      raise Error, "#{e.class}: #{e.message}"
    end

    private

    attr_reader :session

    def perform(uri)
      return session.call(uri) if session

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.1"
      request["Accept-Encoding"] = "gzip, deflate"

      http.request(request)
    end

    def decode(response)
      body = response.body.to_s
      raise Error, "empty response body" if body.empty?
      raise Error, "feed larger than #{MAX_BODY_BYTES} bytes" if body.bytesize > MAX_BODY_BYTES

      body = case response["content-encoding"].to_s.downcase
      when "gzip" then gunzip(body)
      when "deflate" then inflate(body)
      else body
      end

      to_utf8(body)
    end

    def gunzip(body)
      Zlib::GzipReader.new(StringIO.new(body)).read
    rescue Zlib::Error => e
      raise Error, "invalid gzip body: #{e.message}"
    end

    def inflate(body)
      Zlib::Inflate.inflate(body)
    rescue Zlib::Error
      # Some servers send raw deflate without the zlib header.
      Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(body)
    rescue Zlib::Error => e
      raise Error, "invalid deflate body: #{e.message}"
    end

    def to_utf8(body)
      body = body.dup.force_encoding(Encoding::UTF_8)
      return body if body.valid_encoding?

      # Feeds that are not valid UTF-8 still have to be parseable, so drop the
      # offending bytes rather than let the XML parser choke. Correct transcoding
      # would need the encoding from the XML prolog; in practice feeds are UTF-8.
      body.scrub("")
    end
  end

  # Swappable default transport. Tests replace it to serve canned feed bodies
  # without opening a socket; production always uses a real HttpTransport.
  class << self
    attr_writer :default_transport

    def default_transport
      @default_transport ||= HttpTransport.new
    end
  end

  # Fetches a URL and creates a Feed from the metadata it advertises. The
  # optional category is a single name (the compact add form), turned into a
  # Category and attached through the association.
  def self.create_from_url(url, category: nil, transport: default_transport)
    parsed = Feedjira.parse(transport.get(url))

    feed = Feed.create!(
      url: url,
      title: plain_text(parsed.title).presence || URI.parse(url).host.to_s,
      site_url: parsed.url,
      description: truncate_text(plain_text(parsed.description), 1_000)
    )

    feed.categories << Category.find_or_create_by_name(category) if category.present?
    feed
  end

  # Refreshes every feed that is due for a poll.
  def self.refresh_due(interval: nil, limit: nil, transport: default_transport)
    interval ||= Integer(ENV.fetch("FEED_REFRESH_MINUTES", 30))
    scope = Feed.stale_before(interval.minutes.ago).order(:last_fetched_at, :id)
    scope = scope.limit(limit) if limit

    scope.map { |feed| new(feed, transport: transport).call }
  end

  def self.plain_text(html)
    return "" if html.nil?

    text = html.to_s
    text = FULL_SANITIZER.sanitize(text) if text.include?("<")
    decode_entities(text).gsub(/\s+/, " ").strip
  end

  def self.truncate_text(text, limit)
    return nil if text.nil?

    text = text.to_s
    text.length > limit ? text[0, limit] : text
  end

  def self.decode_entities(text)
    CGI.unescapeHTML(text)
  rescue ArgumentError
    text
  end
  private_class_method :decode_entities

  def initialize(feed, transport: self.class.default_transport)
    @feed = feed
    @transport = transport
  end

  attr_reader :feed, :transport

  def call
    parsed = Feedjira.parse(transport.get(feed.url))
    new_count = persist_entries(parsed.entries)

    # On success the error is cleared and the poll time recorded, so the feed
    # drops out of the "due" set until the next refresh interval elapses.
    feed.update!(
      last_fetched_at: Time.current,
      last_error: nil,
      title: self.class.plain_text(parsed.title).presence || feed.title,
      site_url: parsed.url.presence || feed.site_url,
      description: self.class.truncate_text(self.class.plain_text(parsed.description), 1_000).presence || feed.description
    )

    Result.new(feed: feed, new_entries: new_count, error: nil)
  rescue StandardError => e
    # Deliberately leaves last_fetched_at untouched so the next cycle retries.
    feed.update(last_error: self.class.truncate_text("#{e.class}: #{e.message}", 500))
    Result.new(feed: feed, new_entries: 0, error: e.message)
  end

  private

  def persist_entries(entries)
    rows = Array(entries).first(DEFAULT_ENTRY_LIMIT).filter_map { |entry| row_for(entry) }
    return 0 if rows.empty?

    before = feed.entries.count
    # unique_by turns conflicting rows into a no-op, so entries already stored
    # are never rewritten by a later poll.
    Entry.insert_all(rows, unique_by: [ :feed_id, :guid ]) # rubocop:disable Rails/SkipsModelValidations
    feed.entries.count - before
  end

  def row_for(entry)
    guid = entry.entry_id.to_s.presence || entry.url.to_s
    url = entry.url.to_s
    return nil if guid.blank? || url.blank?

    now = Time.current
    {
      feed_id: feed.id,
      guid: self.class.truncate_text(guid, 500),
      url: self.class.truncate_text(url, 1_000),
      title: self.class.truncate_text(self.class.plain_text(entry.title).presence || "(untitled)", 500),
      author: self.class.truncate_text(self.class.plain_text(entry_author(entry)), 200).presence,
      published_at: entry_time(entry),
      summary: self.class.truncate_text(self.class.plain_text(entry_body(entry)), 4_000).presence,
      created_at: now,
      updated_at: now
    }
  end

  def entry_author(entry)
    entry.author if entry.respond_to?(:author)
  end

  def entry_body(entry)
    if entry.respond_to?(:summary) && entry.summary.present?
      entry.summary
    elsif entry.respond_to?(:content)
      entry.content
    end
  end

  def entry_time(entry)
    published = entry.published if entry.respond_to?(:published)
    published || (entry.updated if entry.respond_to?(:updated))
  end
end
