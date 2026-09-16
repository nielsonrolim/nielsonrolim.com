# One language edition of a clipping. A story can be published in several
# languages, each at its own URL, so the content (url, title, summary) lives here
# per locale rather than on the clipping.
#
# The URL is optional: most articles are published in a single language, and the
# other language's variant is only a translation, with no page of its own. Readers
# of that language get the translated text and the URL of the edition that exists.
#
# `origin` records how the content got here: `generated` by the summary run, or
# `manual` when the reader wrote or corrected it by hand. A manual variant is
# never overwritten by a later generation.
class ClippingVariant < ApplicationRecord
  include SupportedLanguages

  belongs_to :clipping

  enum :origin, {
    generated: "generated",
    manual: "manual"
  }

  validates :locale, inclusion: { in: LANGUAGES }, allow_nil: true
  validates :title, presence: true
  # Optional: a variant that only holds a machine translation has no page of its
  # own, and readers fall back to the URL of the edition that exists.
  validates :url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, allow_nil: true
  validate :single_sourceless_variant

  scope :ordered, -> { order(Arel.sql("locale IS NULL DESC"), :locale) }

  private

  # The source edition is created before the language is known, so there is at
  # most one locale-less variant per clipping. The partial unique index backs
  # this up against races.
  def single_sourceless_variant
    return if locale.present? || clipping.blank?

    others = clipping.variants.reject { |variant| variant.equal?(self) }
    return if others.none? { |variant| variant.locale.blank? && !variant.marked_for_destruction? }

    errors.add(:locale, :taken)
  end
end
