require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "expires after the configured duration" do
    session = users(:admin).sessions.create!

    assert_not_nil session.expires_at
    assert_not session.expired?
  end

  test "an expired session reports itself as expired" do
    session = users(:admin).sessions.create!
    session.update_columns(expires_at: 1.minute.ago)

    assert session.expired?
  end
end
