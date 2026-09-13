require "test_helper"

class SubscriberTest < ActiveSupport::TestCase
  test "valid with a proper email" do
    subscriber = Subscriber.new(email: "reader@example.com")
    assert subscriber.valid?
  end

  test "invalid without an email" do
    subscriber = Subscriber.new(email: nil)
    assert_not subscriber.valid?
  end

  test "invalid with a malformed email" do
    subscriber = Subscriber.new(email: "not-an-email")
    assert_not subscriber.valid?
  end

  test "invalid with a duplicate email regardless of case" do
    Subscriber.create!(email: "reader@example.com")
    duplicate = Subscriber.new(email: "READER@example.com")
    assert_not duplicate.valid?
  end
end
