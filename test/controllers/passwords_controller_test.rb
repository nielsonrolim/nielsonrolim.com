require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { @user = users(:admin) }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create enqueues a reset email" do
    post passwords_path, params: { email_address: @user.email_address }

    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }

    assert_enqueued_emails 0
    assert_redirected_to new_session_path
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with an invalid password reset token" do
    get edit_password_path("invalid token")

    assert_redirected_to new_password_path
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "new", password_confirmation: "new" }

      assert_redirected_to new_session_path
    end
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token

    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "no", password_confirmation: "match" }

      assert_redirected_to edit_password_path(token)
    end
  end

  test "update ends the user's sessions" do
    sign_in_as(@user)

    assert_difference -> { @user.sessions.count }, -1 do
      put password_path(@user.password_reset_token), params: { password: "new", password_confirmation: "new" }
    end
  end
end
