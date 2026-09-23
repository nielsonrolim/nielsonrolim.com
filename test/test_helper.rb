ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "support/fakes"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include ActiveJob::TestHelper
    include HttpResponseHelpers
    include OpencodeEventHelpers

    # Add more helper methods to be used by all tests here...
  end
end

module ActionDispatch
  class IntegrationTest
    include HttpResponseHelpers
    include OpencodeEventHelpers

    # The /admin area is behind a session (see Admin::BaseController). Most
    # controller tests only need to be signed in; the real login flow is covered
    # by Admin::AuthenticationTest.
    def sign_in_as_admin
      sign_in_as(users(:admin))
    end
  end
end
