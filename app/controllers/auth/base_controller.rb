module Auth
  # Base class for the login and password-reset pages.
  #
  # They share a minimal layout and, like the admin area, are not locale-scoped
  # in the router, so their generated URLs carry no ?locale=.
  class BaseController < ApplicationController
    layout "auth"

    private

    def default_url_options
      {}
    end
  end
end
