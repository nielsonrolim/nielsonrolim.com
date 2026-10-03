# Validation and normalisation for the third-party URLs the app stores (feeds,
# entries, clipping editions). A feed is attacker-controlled input, so a URL
# must be a plain http(s) address and nothing else.
module SafeUrl
  extend ActiveSupport::Concern

  # Anchored on purpose. Rails' `format` validator runs `match?`, which finds a
  # match anywhere in the string, so the usual
  # `URI::DEFAULT_PARSER.make_regexp(%w[http https])` accepts a payload such as
  # "javascript:alert(1) https://example.com". `[^\s]+` additionally rules out
  # embedded whitespace.
  SAFE_URL_PATTERN = %r{\Ahttps?://[^\s]+\z}i

  # The value when it is a safe http(s) URL, otherwise nil. Used on ingest,
  # where Feedjira hands us raw feed data that never runs model validations.
  def self.safe(value)
    text = value.to_s
    text.match?(SAFE_URL_PATTERN) ? text : nil
  end

  # The host of a URL, lower-cased, or "" when it cannot be parsed. The one place
  # the app turns a URL into its host, so the create form's host placeholder and
  # the variant that compares against it always agree.
  def self.host(value)
    URI.parse(value.to_s).host.to_s.downcase
  rescue URI::InvalidURIError
    ""
  end

  class_methods do
    # `allow_blank` is for the optional URL of a translation-only clipping
    # edition; required URLs rely on their own presence validation.
    def validates_safe_url(attribute, allow_blank: false)
      validates attribute, format: { with: SAFE_URL_PATTERN, allow_blank: allow_blank }
    end
  end
end
