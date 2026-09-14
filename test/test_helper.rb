ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
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

    # The reader area is behind HTTP Basic Auth (see Reader::BaseController).
    READER_CREDENTIALS = { "READER_USERNAME" => "reader", "READER_PASSWORD" => "s3cret" }.freeze

    def with_reader_credentials
      previous = READER_CREDENTIALS.keys.to_h { |key| [ key, ENV[key] ] }
      READER_CREDENTIALS.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    # The reader must fail closed when it is not configured.
    def without_reader_credentials
      previous = READER_CREDENTIALS.keys.to_h { |key| [ key, ENV[key] ] }
      READER_CREDENTIALS.each_key { |key| ENV.delete(key) }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value unless value.nil? }
    end

    # For tests that make several authenticated requests: set the ENV once in
    # setup and restore it in teardown, so follow-ups keep working.
    def set_reader_credentials!
      @reader_env_backup = READER_CREDENTIALS.keys.to_h { |key| [ key, ENV[key] ] }
      READER_CREDENTIALS.each { |key, value| ENV[key] = value }
    end

    def unset_reader_credentials!
      @reader_env_backup = READER_CREDENTIALS.keys.to_h { |key| [ key, ENV[key] ] }
      READER_CREDENTIALS.each_key { |key| ENV.delete(key) }
    end

    def restore_reader_credentials!
      (@reader_env_backup || {}).each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
      @reader_env_backup = nil
    end

    def reader_headers(user = "reader", password = "s3cret")
      credentials = ActionController::HttpAuthentication::Basic.encode_credentials(user, password)
      { "HTTP_AUTHORIZATION" => credentials }
    end

    def get_as_reader(path, **options)
      get path, **options.merge(headers: reader_headers.merge(options[:headers].to_h))
    end

    def post_as_reader(path, **options)
      post path, **options.merge(headers: reader_headers.merge(options[:headers].to_h))
    end

    def delete_as_reader(path, **options)
      delete path, **options.merge(headers: reader_headers.merge(options[:headers].to_h))
    end
  end
end
