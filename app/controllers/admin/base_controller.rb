module Admin
  # Base class for the private admin area.
  #
  # Every route under /admin requires a session (see the Authentication concern
  # and SessionsController). The area fails closed: if no admin user exists yet,
  # requests get a 403 rather than a login page that cannot possibly succeed.
  class BaseController < ApplicationController
    before_action :deny_when_no_admin_user
    before_action :require_authentication

    layout "admin"

    private

    # The admin area is not locale-scoped in the router, so do not append ?locale=
    # to every generated URL the way ApplicationController does.
    def default_url_options
      {}
    end

    def deny_when_no_admin_user
      return if User.exists?

      Rails.logger.error("[admin] no admin user exists; denying access")
      head :forbidden
    end
  end
end
