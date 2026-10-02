require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "renders an http URL as-is" do
    assert_equal "https://example.com/a", safe_url("https://example.com/a")
  end

  test "neutralises a javascript URL" do
    assert_equal "#", safe_url("javascript:alert(1)")
  end

  test "neutralises an http URL with a smuggled scheme" do
    assert_equal "#", safe_url("javascript:alert(1) https://example.com/a")
  end

  test "neutralises a data URL" do
    assert_equal "#", safe_url("data:text/html,<script>alert(1)</script>")
  end

  test "neutralises a missing URL" do
    assert_equal "#", safe_url(nil)
  end
end
