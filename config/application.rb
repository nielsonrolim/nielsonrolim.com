require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NielsonrolimCom
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.time_zone = ENV.fetch("APP_TIME_ZONE", "Brasilia")

    config.active_job.queue_adapter = :solid_queue
    # Point Solid Queue's models at the `queue` database from config/database.yml
    # instead of the primary one.
    config.solid_queue.connects_to = { database: { writing: :queue } }

    # The job dashboard (Mission Control) exposes job arguments — prompts and
    # subscriber addresses — so it inherits the admin area's session login. Its
    # own basic auth is turned off because Admin::BaseController already requires
    # a session and fails closed when no admin user exists.
    config.mission_control.jobs.base_controller_class = "Admin::BaseController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    config.i18n.default_locale = :"pt-BR"
    config.i18n.available_locales = [ :"pt-BR", :"en-US" ]
  end
end
