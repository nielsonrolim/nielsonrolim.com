require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "root redirects to the default locale" do
    get "/"
    assert_redirected_to "/pt-BR"
  end

  test "home responds successfully in pt-BR" do
    get "/pt-BR"
    assert_response :success
    assert_select "h1", "Nielson Rolim"
  end

  test "home responds successfully in en-US" do
    get "/en-US"
    assert_response :success
    assert_select "h1", "Nielson Rolim"
  end

  test "home renders the terminal prompt and locale switcher" do
    get "/pt-BR"
    assert_select ".terminal__prompt", minimum: 1
    assert_select "a.locale-switch__link[href=?]", "/en-US"
  end

  test "home lists work experience in pt-BR" do
    get "/pt-BR"
    assert_select "body", /Light Labs Inc/
    assert_select "body", /Fluxx/
  end

  test "home lists work experience in en-US" do
    get "/en-US"
    assert_select "body", /Light Labs Inc/
    assert_select "body", /Fluxx/
  end
end
