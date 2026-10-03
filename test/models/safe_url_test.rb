require "test_helper"

class SafeUrlTest < ActiveSupport::TestCase
  test "returns the host, lower-cased" do
    assert_equal "example.com", SafeUrl.host("https://EXAMPLE.com/path")
  end

  test "keeps subdomains, stripping nothing" do
    assert_equal "www.example.com", SafeUrl.host("https://www.example.com/news")
  end

  test "is empty for something that is not a URL" do
    assert_equal "", SafeUrl.host("not-a-url")
    assert_equal "", SafeUrl.host(nil)
  end
end
