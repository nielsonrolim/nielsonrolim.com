require "net/http"
require "zlib"
require "stringio"

# The HTTP half of any outbound fetch: follows redirects, inflates compressed
# bodies, enforces a size cap and returns UTF-8 text.
#
# `session` performs one request for a URI and returns a Net::HTTPResponse. It is
# injectable so tests can drive redirects and encodings without sockets.
class HttpTransport
  Error = Class.new(StandardError)

  USER_AGENT = "nielsonrolim.com (+https://nielsonrolim.com)"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 20
  MAX_REDIRECTS = 5
  MAX_BODY_BYTES = 5 * 1024 * 1024

  FEED_ACCEPT = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.1"
  HTML_ACCEPT = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

  # Swappable default. Tests replace it to serve canned bodies without opening a
  # socket; production always uses a real transport.
  class << self
    attr_writer :default

    def default
      @default ||= new
    end
  end

  def initialize(session: nil)
    @session = session
  end

  def get(url, accept: FEED_ACCEPT, redirects_left: MAX_REDIRECTS)
    raise Error, "too many redirects" if redirects_left.negative?

    uri = URI.parse(url.to_s)
    raise Error, "unsupported URL: #{url}" unless uri.is_a?(URI::HTTP) && uri.host.present?

    response = perform(uri, accept)

    case response
    when Net::HTTPSuccess
      decode(response)
    when Net::HTTPRedirection
      location = response["location"]
      raise Error, "redirect without a Location header" if location.blank?

      get(URI.join(uri, location).to_s, accept: accept, redirects_left: redirects_left - 1)
    else
      raise Error, "HTTP #{response.code} for #{uri}"
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError,
         Net::OpenTimeout, Net::ReadTimeout, IOError, OpenSSL::SSL::SSLError, URI::InvalidURIError => e
    raise Error, "#{e.class}: #{e.message}"
  end

  private

  attr_reader :session

  def perform(uri, accept)
    return session.call(uri) if session

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = accept
    request["Accept-Encoding"] = "gzip, deflate"

    http.request(request)
  end

  def decode(response)
    body = response.body.to_s
    raise Error, "empty response body" if body.empty?
    raise Error, "body larger than #{MAX_BODY_BYTES} bytes" if body.bytesize > MAX_BODY_BYTES

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

    # A body that is not valid UTF-8 still has to be parseable, so drop the
    # offending bytes rather than let the parser choke. Correct transcoding would
    # need the encoding from the document itself; in practice these are UTF-8.
    body.scrub("")
  end
end
