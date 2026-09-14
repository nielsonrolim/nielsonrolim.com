class Clipping < ApplicationRecord
  include SupportedLanguages

  # A clipping usually comes from a feed entry, but can also be added by hand
  # from a URL, in which case there is no entry behind it.
  belongs_to :entry, optional: true
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
  validate :url_not_already_queued
  validate :entry_not_already_queued

  scope :unsent, -> { where(newsletter_id: nil) }
  scope :queued, -> { unsent.order(:created_at) }

  # What the next issue can actually carry. A clipping whose summary failed has
  # nothing to show, so it waits in the queue until it is fixed or removed.
  scope :shippable, -> { unsent.where.not(summary_status: :failed) }

  # A clipping created as already failed (no source to summarize) must not kick
  # off a generation run.
  after_create_commit :enqueue_summary_generation, if: :pending?

  # The text the summary is generated from: the feed entry's own summary, or the
  # article text stored when the clipping was added by hand.
  def summary_source
    entry&.summary.presence || source_text
  end

  # Added by hand from a URL, with no feed entry behind it.
  def manual?
    entry_id.blank?
  end

  # `title`/`summary` hold the original, in `language`; the translated columns
  # hold the other language.
  def other_locale
    SupportedLanguages.other(language)
  end

  # The title to show in `locale`: the original when it already is that language
  # (or nothing has been translated yet), the translation otherwise.
  def title_for(locale)
    return title if original_for?(locale)

    title_translated
  end

  def summary_for(locale)
    return summary if original_for?(locale)

    summary_translated
  end

  # The stored value for a locale, with no fallback, for the edit form: what the
  # user edits per language and what gets written back to the columns.
  def stored_title(locale)
    source_column?(locale) ? title : title_translated
  end

  def stored_summary(locale)
    source_column?(locale) ? summary : summary_translated
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

  # Which of the two columns physically holds `locale`. With no detected language
  # the originals are treated as the first locale's, so the form has somewhere to
  # show them.
  def source_column?(locale)
    locale.to_s == (language.presence || LANGUAGES.first)
  end

  # The partial unique index on entry_id guards against races; this gives a
  # friendly validation error for the common case. Manual clippings have no entry,
  # so the index does not cover them.
  def entry_not_already_queued
    return if entry_id.blank?

    if Clipping.unsent.where(entry_id: entry_id).where.not(id: id).exists?
      errors.add(:entry, :taken)
    end
  end

  # Manually added clippings are matched by URL instead, which also catches one
  # that duplicates something already queued from a feed.
  def url_not_already_queued
    return if url.blank? || entry_id.present?

    scope = Clipping.unsent.where("lower(url) = ?", url.downcase)
    scope = scope.where.not(id: id) if id

    errors.add(:url, :taken) if scope.exists?
  end

  def enqueue_summary_generation
    GenerateSummaryJob.perform_later(id)
  end
end
