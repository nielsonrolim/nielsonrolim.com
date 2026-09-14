class Clipping < ApplicationRecord
  include SupportedLanguages

  belongs_to :entry
  belongs_to :newsletter, optional: true

  enum :summary_status, {
    pending: "pending",
    summarizing: "summarizing",
    summarized: "summarized",
    failed: "failed"
  }

  validates :title, presence: true
  validates :url, presence: true,
                  format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :language, inclusion: { in: LANGUAGES }, allow_nil: true
  validate :entry_not_already_queued

  scope :unsent, -> { where(newsletter_id: nil) }
  scope :queued, -> { unsent.order(:created_at) }

  after_create_commit :enqueue_summary_generation

  # `title` and `summary` hold the original, in `language`. `title_translated`
  # and `summary_translated` hold the other language.
  def other_locale
    SupportedLanguages.other(language)
  end

  # The title to show in `locale`: the original when it is already that
  # language (or nothing has been translated yet), the translation otherwise.
  def title_for(locale)
    return title if original_for?(locale)

    title_translated
  end

  def summary_for(locale)
    return summary if original_for?(locale)

    summary_translated
  end

  # Whether the other language's version exists yet.
  def translated?
    language.present? && (title_translated.present? || summary_translated.present?)
  end

  # Stores one generation result: the detected language, the translated title and
  # the summary in each language. `summary` becomes the one in the article's own
  # language.
  def apply_summary(result)
    self.language = result.language
    self.title_translated = result.title_translated
    self.summary = result.summary_for(result.language)
    self.summary_translated = result.summary_for(other_locale)
    self.summary_status = :summarized
    self.summary_error = nil
  end

  private

  def original_for?(locale)
    locale.to_s == language.to_s || title_translated.blank?
  end

  # The partial unique index on entry_id guards against races; this gives a
  # friendly validation error for the common case.
  def entry_not_already_queued
    return if newsletter_id.present?

    if Clipping.unsent.where(entry_id: entry_id).where.not(id: id).exists?
      errors.add(:entry, :taken)
    end
  end

  def enqueue_summary_generation
    GenerateSummaryJob.perform_later(id)
  end
end
