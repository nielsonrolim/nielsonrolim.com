require "test_helper"

class PreferencesControllerTest < ActionDispatch::IntegrationTest
  test "shows the address and the current language" do
    subscriber = subscribers(:second) # en-US

    get preferences_path(token: subscriber.unsubscribe_token)

    assert_response :success
    assert_select "body", /clipping-reader@example\.org/
    assert_select "select[name=?] option[selected][value=?]", "subscriber[language]", "en-US"
  end

  test "the page follows the subscriber's language" do
    get preferences_path(token: subscribers(:second).unsubscribe_token) # en-US
    assert_response :success
    assert_select "h1", "Subscription preferences"

    get preferences_path(token: subscribers(:first).unsubscribe_token) # pt-BR
    assert_select "h1", "Preferências da inscrição"
  end

  test "changing the language saves it" do
    subscriber = subscribers(:first) # pt-BR

    assert_no_difference -> { Subscriber.count } do
      patch preferences_path(token: subscriber.unsubscribe_token),
            params: { subscriber: { language: "en-US" } }
    end

    assert_equal "en-US", subscriber.reload.language
    assert_redirected_to preferences_path(token: subscriber.unsubscribe_token)
  end

  test "the confirmation comes in the language just chosen" do
    subscriber = subscribers(:first) # pt-BR

    patch preferences_path(token: subscriber.unsubscribe_token),
          params: { subscriber: { language: "en-US" } }

    follow_redirect!
    assert_select ".flash--notice", /Language updated to en-US/
  end

  test "a language the site does not speak is refused" do
    subscriber = subscribers(:first)

    patch preferences_path(token: subscriber.unsubscribe_token),
          params: { subscriber: { language: "de-DE" } }

    assert_equal "pt-BR", subscriber.reload.language
    assert_response :redirect
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "an unknown token renders nothing-to-manage instead of a 404" do
    get preferences_path(token: "not-a-real-token")

    assert_response :success
    assert_select "body", /Nada para gerenciar/
  end

  test "a blank token renders nothing-to-manage" do
    get preferences_path

    assert_response :success
    assert_select "body", /Nada para gerenciar/
  end

  test "an unknown token cannot change anybody" do
    assert_no_changes -> { subscribers(:first).reload.language } do
      patch preferences_path(token: "nope"), params: { subscriber: { language: "en-US" } }
    end

    assert_response :success
  end

  test "changing one subscriber does not touch another" do
    patch preferences_path(token: subscribers(:first).unsubscribe_token),
          params: { subscriber: { language: "en-US" } }

    assert_equal "en-US", subscribers(:second).reload.language
  end

  test "the page links to the unsubscribe page" do
    get preferences_path(token: subscribers(:first).unsubscribe_token)

    assert_select "a[href^=?]", "/newsletter/unsubscribe"
    assert_select "a[href*=?]", subscribers(:first).unsubscribe_token
  end
end
