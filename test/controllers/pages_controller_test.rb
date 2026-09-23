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

  test "the newsletter signup sits right above the experience section" do
    get "/pt-BR"

    body = response.body
    newsletter = body.index(I18n.t("pages.home.newsletter.prompt"))
    experience = body.index(I18n.t("pages.home.experience.prompt"))

    assert_not_nil newsletter
    assert_not_nil experience
    assert_operator newsletter, :<, experience
  end

  test "the newsletter page presents the newsletter in pt-BR" do
    get "/pt-BR/newsletter"

    assert_response :success
    assert_select "h3", "Receba uma newsletter sobre tecnologia."
    assert_select "body", /clipping com resumo direto no seu e-mail/
  end

  test "the newsletter page responds in en-US" do
    get "/en-US/newsletter"

    assert_response :success
    assert_select "h3", "Get a newsletter about tech."
  end

  test "the newsletter page form posts to the signup endpoint in its locale" do
    get "/en-US/newsletter"

    assert_select "form[action=?]", "/subscribers?locale=en-US"
    assert_select "form input[name=?]", "subscriber[email]"
    assert_select "form input[name=?][value=?]", "from", "newsletter"
    assert_select "form input[name=?]", "subscriber[nickname]"
  end

  test "home presents the newsletter with a heading and the shared text" do
    get "/pt-BR"
    assert_select "h3", "Receba uma newsletter sobre tecnologia."
    assert_select "body", /Toda semana eu escolho os links/

    get "/en-US"
    assert_select "h3", "Get a newsletter about tech."
    assert_select "body", /Every week I pick the tech links/
  end
end
