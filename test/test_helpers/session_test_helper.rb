module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  # Tolerates the session row having been removed underneath us (e.g. a test that
  # deletes the users to exercise the fail-closed path).
  def sign_out
    Current.session&.destroy! unless Current.session&.destroyed?
    Current.session = nil
    cookies.delete("session_id")
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
