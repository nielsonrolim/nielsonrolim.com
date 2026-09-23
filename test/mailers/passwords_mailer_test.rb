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
end
