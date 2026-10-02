require "net/http"
require "zlib"
require "stringio"
require "resolv"
require "ipaddr"

# The HTTP half of any outbound fetch: follows redirects, inflates compressed
# bodies, enforces a size cap and returns UTF-8 text.
#
# `session` performs one request for a URI and returns a Net::HTTPResponse. It is
# injectable so tests can drive redirects and encodings without sockets.
#
# A fetched URL is third-party, attacker-influenced data (it comes from feed
# content), so every hop is checked against the SSRF guard before it is dialled.
class HttpTransport
  Error = Class.new(StandardError)

  USER_AGENT = "nielsonrolim.com (+https://nielsonrolim.com)"
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 20
  MAX_REDIRECTS = 5
  MAX_BODY_BYTES = 5 * 1024 * 1024

  # How much compressed data is fed to the inflater, and how much decompressed
  # data is read, before the running size is checked again. Bounds the memory a
  # decompression bomb can grow to a single chunk past the cap.
  CHUNK_BYTES = 64 * 1024

  FEED_ACCEPT = "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.1"
  HTML_ACCEPT = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

  # Swappable defaults. Tests replace them to serve canned bodies or to resolve
  # every host to a public address without touching DNS; production uses a real
  # transport and the system resolver.
  class << self
    attr_writer :default, :resolver

    def default
      @default ||= new
    end

    # Returns the addresses a host resolves to. Injectable so the SSRF guard can
    # be tested without a network.
    def resolver
      @resolver ||= ->(host) { Resolv.getaddresses(host) }
    end
  end

  def initialize(session: nil, resolver: nil)
    @session = session
    @resolver = resolver
  end

  def get(url, accept: FEED_ACCEPT, redirects_left: MAX_REDIRECTS)
    raise Error, "too many redirects" if redirects_left.negative?

    uri = URI.parse(url.to_s)
    raise Error, "unsupported URL: #{url}" unless uri.is_a?(URI::HTTP) && uri.host.present?

    assert_public_host!(uri)
    response = perform(uri, accept)

    case response
    when Net::HTTPSuccess
      decode(response)
    when Net::HTTPRedirection
      location = response["location"]
      raise Error, "redirect without a Location header" if location.blank?

      # Recurse instead of looping so the target host goes through the same
      # guard: a public URL must not be allowed to redirect to an internal one.
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

  # Refuses to connect to loopback, private, link-local (cloud metadata) or
  # otherwise unroutable addresses. Fails closed: a host that does not resolve
  # is treated as unsafe.
  def assert_public_host!(uri)
    addresses = resolved_addresses(uri.hostname)
    raise Error, "could not resolve #{uri.hostname}" if addresses.blank?
    raise Error, "blocked address for #{uri.hostname}" if addresses.any? { |address| internal_address?(address) }
  end

  def resolved_addresses(host)
    [ IPAddr.new(host).to_s ]
  rescue IPAddr::InvalidAddressError
    (resolver || self.class.resolver).call(host)
  end

  # loopback? covers 127/8 and ::1; private? covers 10/8, 172.16/12, 192.168/16
  # and IPv6 ULA; link_local? covers 169.254/16 (including the 169.254.169.254
  # metadata endpoint) and fe80::/10.
  def internal_address?(address)
    ip = IPAddr.new(address.to_s)
    ip.loopback? || ip.private? || ip.link_local? ||
      [ "0.0.0.0", "::" ].include?(ip.to_s)
  rescue IPAddr::InvalidAddressError
    true
  end

  def resolver
    @resolver
  end

  def perform(uri, accept)
    return session.call(uri) if session

    http = Net::HTTP.new(uri.hostname, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = accept
    request["Accept-Encoding"] = "gzip, deflate"

    # The block form lets the body be read in chunks and abandoned as soon as it
    # passes the cap, instead of buffering an unbounded response first.
    http.request(request) do |response|
      body = read_capped_body(response)
      response.instance_variable_set(:@body, body)
      response.instance_variable_set(:@read, true)
    end
  end

  def read_capped_body(response)
    body = +""
    response.read_body do |chunk|
      body << chunk
      raise Error, "body larger than #{MAX_BODY_BYTES} bytes" if body.bytesize > MAX_BODY_BYTES
    end
    body
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
    read_capped(Zlib::GzipReader.new(StringIO.new(body)))
  rescue Zlib::Error => e
    raise Error, "invalid gzip body: #{e.message}"
  end

  def inflate(body)
    read_inflated(body, Zlib::MAX_WBITS)
  rescue Zlib::Error
    begin
      read_inflated(body, -Zlib::MAX_WBITS)
    rescue Zlib::Error => e
      raise Error, "invalid deflate body: #{e.message}"
    end
  end

  # Reads an IO in chunks, aborting once the decompressed size passes the cap.
  # A response that expands to gigabytes never materialises.
  def read_capped(io)
    output = +""
    while (chunk = io.read(CHUNK_BYTES))
      output << chunk
      raise Error, "body larger than #{MAX_BODY_BYTES} bytes after decompression" if output.bytesize > MAX_BODY_BYTES
    end
    output
  end

  # Same bound for the streaming inflater, which takes compressed input rather
  # than exposing an IO: feed it in chunks and check after each.
  def read_inflated(body, window_bits)
    inflater = Zlib::Inflate.new(window_bits)
    output = +""
    offset = 0
    while offset < body.bytesize
      output << inflater.inflate(body.byteslice(offset, CHUNK_BYTES))
      raise Error, "body larger than #{MAX_BODY_BYTES} bytes after decompression" if output.bytesize > MAX_BODY_BYTES
      offset += CHUNK_BYTES
    end
    output << inflater.finish
    raise Error, "body larger than #{MAX_BODY_BYTES} bytes after decompression" if output.bytesize > MAX_BODY_BYTES

    output
  ensure
    inflater&.close
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
