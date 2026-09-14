module Reader
  # Base class for the private reader area.
  #
  # Every route under /reader is behind HTTP Basic Auth. Credentials come from
  # the environment, and the area fails closed: if either is missing, requests
  # get a 403 rather than becoming world-readable.
  class BaseController < ApplicationController
    before_action :require_reader_credentials

    layout "reader"

    private

    # The reader is not locale-scoped in the router, so do not append ?locale=
    # to every generated URL the way ApplicationController does.
    def default_url_options
      {}
    end

    def require_reader_credentials
      username = ENV["READER_USERNAME"].presence
      password = ENV["READER_PASSWORD"].presence

      if username.blank? || password.blank?
        Rails.logger.error("[reader] READER_USERNAME/READER_PASSWORD are not set; denying access")
        head :forbidden
        return
      end

      authenticate_or_request_with_http_basic(t("reader.realm")) do |name, given_password|
        # Non-short-circuiting & so both comparisons always run.
        ActiveSupport::SecurityUtils.secure_compare(name.to_s, username) &
          ActiveSupport::SecurityUtils.secure_compare(given_password.to_s, password)
      end
    end
  end
end
