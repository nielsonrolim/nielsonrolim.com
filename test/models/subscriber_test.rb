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

  test "the languages are the site's locales" do
    assert_equal %w[pt-BR en-US], Subscriber::LANGUAGES
  end

  test "defaults to the site's default language" do
    assert_equal "pt-BR", Subscriber.new(email: "new@example.com").language
  end

  test "rejects a language the site does not speak" do
    subscriber = Subscriber.new(email: "new@example.com", language: "de-DE")

    assert_not subscriber.valid?
    assert_includes subscriber.errors.attribute_names, :language
  end

  test "accepts every available language" do
    Subscriber::LANGUAGES.each_with_index do |language, index|
      assert Subscriber.new(email: "lang#{index}@example.com", language: language).valid?
    end
  end

  test "search matches a partial email, ignoring case" do
    results = Subscriber.search("CLIPPING")

    assert_includes results, subscribers(:first)
    assert_includes results, subscribers(:second)
  end

  test "search narrows by fragment" do
    results = Subscriber.search("fan@")

    assert_includes results, subscribers(:first)
    assert_not_includes results, subscribers(:second)
  end

  test "search with a blank term returns everyone" do
    assert_equal Subscriber.count, Subscriber.search("  ").count
  end

  test "search treats a LIKE wildcard as a literal" do
    assert_empty Subscriber.search("%")
  end

  test "to_csv exports the email, language and join date" do
    csv = Subscriber.to_csv(Subscriber.where(id: subscribers(:second).id))

    lines = CSV.parse(csv)
    assert_equal %w[email language created_at], lines.first
    assert_equal [ "clipping-reader@example.org", "en-US" ], lines.second.first(2)
  end
end
