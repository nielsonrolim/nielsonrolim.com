# The languages the site speaks. Shared by everything that stores content per
# language (subscribers, clippings) so adding a locale is a single edit.
module SupportedLanguages
  extend ActiveSupport::Concern

  LANGUAGES = I18n.available_locales.map(&:to_s).freeze

  # The language that is not `locale`. With two locales that is unambiguous, and
  # unknown languages have no "other".
  def self.other(locale)
    return nil if locale.blank?

    (LANGUAGES - [ locale.to_s ]).first
  end
end
