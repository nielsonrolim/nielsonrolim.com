require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset email is localized and carries the reset link" do
    user = users(:admin)
    email = PasswordsMailer.reset(user)

    assert_equal [ user.email_address ], email.to
    assert_equal I18n.t("auth.passwords.mailer.subject"), email.subject
    assert_match I18n.t("auth.passwords.mailer.intro"), email.text_part.body.to_s
    assert_match %r{/passwords/.+/edit}, email.text_part.body.to_s
    assert_match %r{/passwords/.+/edit}, email.html_part.body.to_s
  end

  test "reset email leaves from the transactional sender, not the newsletter" do
    email = PasswordsMailer.reset(users(:admin))

    assert_equal [ "nao-responda@nielsonrolim.com" ], email.from
    refute_includes Array(email.from), "newsletter@nielsonrolim.com"
  end

  test "preheader is present in the html body and absent from the text body" do
    email = PasswordsMailer.reset(users(:admin))
    preheader = I18n.t("auth.passwords.mailer.preheader")

    assert_match preheader, email.html_part.body.to_s
    refute_match preheader, email.text_part.body.to_s
  end

  test "reset link appears in both the html and text bodies" do
    email = PasswordsMailer.reset(users(:admin))

    assert_match %r{/passwords/.+/edit}, email.html_part.body.to_s
    assert_match %r{/passwords/.+/edit}, email.text_part.body.to_s
  end

  test "html cta and fallback use the same reset token" do
    email = PasswordsMailer.reset(users(:admin))
    urls = email.html_part.body.to_s.scan(%r{href="(https?://[^"]+/passwords/[^"]+/edit)"}).flatten

    assert_equal 2, urls.size
    assert_equal 1, urls.uniq.size
  end
end
