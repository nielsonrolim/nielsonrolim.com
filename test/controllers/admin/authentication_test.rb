require "test_helper"

class Admin::AuthenticationTest < ActionDispatch::IntegrationTest
  # Every route under /admin: the dashboard, the job dashboard, and the reader
  # that is nested underneath it.
  ADMIN_PATHS = %w[
    /admin
    /admin/jobs
    /admin/reader
    /admin/reader/feeds
    /admin/reader/entries
    /admin/reader/clippings
    /admin/reader/newsletters
  ].freeze

  test "redirects to the login page when there is no session" do
    get admin_root_path

    assert_redirected_to new_session_path
  end

  test "rejects the wrong password" do
    post session_path, params: { email_address: users(:admin).email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "rejects an unknown email address" do
    post session_path, params: { email_address: "intruder@example.com", password: "password" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "signs in with the right credentials" do
    post session_path, params: { email_address: users(:admin).email_address, password: "password" }

    assert_redirected_to admin_root_path
    assert cookies[:session_id]

    get admin_root_path
    assert_response :success
  end

  test "returns to the intercepted admin page after signing in" do
    get reader_feeds_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: users(:admin).email_address, password: "password" }

    assert_redirected_to reader_feeds_path
  end

  test "signs out" do
    sign_in_as_admin

    delete logout_path

    assert_redirected_to new_session_path

    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "every admin route is protected, including the nested reader" do
    ADMIN_PATHS.each do |path|
      get path
      # The literal path, not new_session_path: inside the mounted Mission
      # Control engine the helper picks up the engine's script_name.
      assert_redirected_to "/login", "expected #{path} to require a session"
    end
  end

  test "fails closed when no admin user exists" do
    User.destroy_all

    ADMIN_PATHS.each do |path|
      get path
      assert_response :forbidden, "expected #{path} to be closed when no user exists"
    end
  end

  test "the public site stays open" do
    get "/pt-BR"

    assert_response :success
  end
end
