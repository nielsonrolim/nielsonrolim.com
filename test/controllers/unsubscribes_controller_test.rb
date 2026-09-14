require "test_helper"

class UnsubscribesControllerTest < ActionDispatch::IntegrationTest
  test "shows a confirmation naming the address" do
    get unsubscribe_path(token: subscribers(:first).unsubscribe_token)

    assert_response :success
    assert_select "body", /clipping-fan@example\.org/
    assert_select "form button", /confirmar cancelamento/
    # The confirmation posts back with the same token.
    assert_select "form[action=?]", unsubscribe_path(token: subscribers(:first).unsubscribe_token)
  end

  test "an unknown token renders the already-gone page instead of a 404" do
    get unsubscribe_path(token: "not-a-real-token")

    assert_response :success
    assert_select "body", /Nada a cancelar/
  end

  test "a blank token renders the already-gone page" do
    get unsubscribe_path

    assert_response :success
    assert_select "body", /Nada a cancelar/
  end

  test "confirming removes the subscriber" do
    subscriber = subscribers(:first)

    assert_difference -> { Subscriber.count }, -1 do
      post unsubscribe_path(token: subscriber.unsubscribe_token)
    end

    assert_redirected_to "/pt-BR"
    assert_nil Subscriber.find_by(id: subscriber.id)
  end

  test "the redirect carries a notice" do
    post unsubscribe_path(token: subscribers(:second).unsubscribe_token)

    follow_redirect!
    assert_select ".flash--notice", /Inscrição cancelada/
  end

  test "unsubscribing twice is harmless" do
    token = subscribers(:first).unsubscribe_token
    post unsubscribe_path(token: token)

    assert_no_difference -> { Subscriber.count } do
      post unsubscribe_path(token: token)
    end

    assert_response :redirect
  end

  test "an unknown token cannot remove anybody" do
    assert_no_difference -> { Subscriber.count } do
      post unsubscribe_path(token: "nope")
    end
  end

  test "one subscriber leaving does not touch the others" do
    post unsubscribe_path(token: subscribers(:first).unsubscribe_token)

    assert_not_nil Subscriber.find_by(email: "clipping-reader@example.org")
  end
end
