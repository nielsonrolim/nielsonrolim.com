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

  test "home shows the theme toggle" do
    get "/pt-BR"
    assert_select "button[data-theme-toggle]"
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

  test "home lists education" do
    get "/pt-BR"
    assert_select "body", /IFPB/
    assert_select "body", /Kapi'olani/
  end

  test "home shows the Jampa Ruby section with logo and links" do
    get "/pt-BR"
    assert_select "img[src*=?]", "jamparuby"
    assert_select "a[href=?]", "https://chat.whatsapp.com/Kan05TwASEtDItNK0ClCJT"
    assert_select "a[href=?]", "https://crudpb.org/"
  end

  test "home lists projects and contact links" do
    get "/pt-BR"
    assert_select "body", /Lavanderia 60 Minutos/
    assert_select "body", /IBAPE-PB/
    assert_select "a[href=?]", "mailto:contato@nielsonrolim.com"
    assert_select "a[href=?]", "https://github.com/nielsonrolim"
    assert_select "a[href=?]", "https://www.linkedin.com/in/nielsonrolim/"
  end
end
