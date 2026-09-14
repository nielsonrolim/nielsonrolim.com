require "test_helper"

class SubscribersControllerTest < ActionDispatch::IntegrationTest
  test "valid signup creates a subscriber and redirects with a notice" do
    assert_difference("Subscriber.count", 1) do
      post "/subscribers", params: { subscriber: { email: "reader@example.com", nickname: "" } }
    end
    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--notice"
  end

  test "an email that is already subscribed gets the success message" do
    Subscriber.create!(email: "reader@example.com")

    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "reader@example.com", nickname: "" } }
    end

    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--notice"
    assert_select ".flash--alert", count: 0
  end

  test "a repeat signup is recognised regardless of case" do
    Subscriber.create!(email: "reader@example.com")

    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "READER@example.com", nickname: "" } }
    end

    follow_redirect!
    assert_select ".flash--notice"
  end

  test "a malformed email is still reported" do
    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "not-an-email", nickname: "" } }
    end

    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "an empty email is still reported" do
    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "", nickname: "" } }
    end

    follow_redirect!
    assert_select ".flash--alert"
  end

  test "filled honeypot silently skips creation but still looks successful" do
    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "bot@example.com", nickname: "i-am-a-bot" } }
    end
    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--notice"
  end

  test "the signup form submits namespaced subscriber params" do
    get "/pt-BR"
    assert_select "form input[name=?]", "subscriber[email]"
    assert_select "form input[name=?]", "subscriber[nickname]"
  end

  test "the signup form posts to the language the visitor is reading" do
    get "/en-US"

    assert_select "form[action=?]", "/subscribers?locale=en-US"
  end

  test "signing up in en-US records the language" do
    post "/subscribers?locale=en-US", params: { subscriber: { email: "english@example.com", nickname: "" } }

    assert_equal "en-US", Subscriber.find_by(email: "english@example.com").language
  end

  test "signing up in pt-BR records the language" do
    post "/subscribers?locale=pt-BR", params: { subscriber: { email: "portuguese@example.com", nickname: "" } }

    assert_equal "pt-BR", Subscriber.find_by(email: "portuguese@example.com").language
  end

  test "signing up without a locale records the default language" do
    post "/subscribers", params: { subscriber: { email: "plain@example.com", nickname: "" } }

    assert_equal "pt-BR", Subscriber.find_by(email: "plain@example.com").language
  end

  test "a crafted language field cannot override the site language" do
    post "/subscribers?locale=en-US",
         params: { subscriber: { email: "crafty@example.com", nickname: "", language: "pt-BR" } }

    assert_equal "en-US", Subscriber.find_by(email: "crafty@example.com").language
  end
end
