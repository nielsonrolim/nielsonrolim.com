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

  test "duplicate email does not create a second subscriber" do
    Subscriber.create!(email: "reader@example.com")

    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "reader@example.com", nickname: "" } }
    end
    assert_redirected_to "/pt-BR"
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
end
