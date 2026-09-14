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

  test "links to the subscription preferences" do
    get unsubscribe_path(token: subscribers(:first).unsubscribe_token)

    assert_select "a[href^=?]", "/newsletter/preferences"
    assert_select "a[href*=?]", subscribers(:first).unsubscribe_token
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

  test "the redirect carries a notice in the subscriber's language" do
    post unsubscribe_path(token: subscribers(:second).unsubscribe_token) # en-US

    # They land on the site in the language they were reading.
    assert_redirected_to "/en-US"
    follow_redirect!
    assert_select ".flash--notice", /Unsubscribed/
  end

  test "a pt-BR subscriber is answered in Portuguese" do
    post unsubscribe_path(token: subscribers(:first).unsubscribe_token)

    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--notice", /Inscrição cancelada/
  end

  test "the page follows the subscriber's language" do
    get unsubscribe_path(token: subscribers(:second).unsubscribe_token) # en-US

    assert_response :success
    assert_select "h1", "Unsubscribe"
    assert_select "form button", /confirm unsubscribe/

    get unsubscribe_path(token: subscribers(:first).unsubscribe_token) # pt-BR

    assert_select "h1", "Cancelar inscrição"
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
