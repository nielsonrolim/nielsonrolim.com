require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:admin) }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to admin_root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(@user)

    delete logout_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "the login page exposes the skip link, main landmark and a labelled theme toggle" do
    get new_session_path

    assert_response :success
    assert_select "a[href=?]", "#main", text: "Pular para o conteúdo"
    assert_select "main#main"
    assert_select "button[data-theme-toggle][aria-pressed=?]", "false"
    assert_no_match(/focus:outline-none/, response.body)
  end
end
