class Clipping < ApplicationRecord
  include SupportedLanguages

  # A clipping usually comes from a feed entry, but can also be added by hand
  # from a URL, in which case there is no entry behind it.
  belongs_to :entry, optional: true
  belongs_to :newsletter, optional: true

  # The language editions of the story: one variant per locale, each with its own
  # URL, title and summary. The variant can exist with no locale yet while the
  # article's language has not been detected.
  has_many :variants, -> { ordered }, class_name: "ClippingVariant",
           inverse_of: :clipping, dependent: :destroy, autosave: true

  enum :summary_status, {
    pending: "pending",
    summarizing: "summarizing",
    summarized: "summarized",
    failed: "failed"
  }

  validates :language, inclusion: { in: LANGUAGES }, allow_nil: true
  validates_associated :variants
  validate :has_a_variant
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

  # Where the clipping came from: the feed for RSS clippings, the publication
  # or channel stored at creation for manual ones.
  def display_source
    entry&.feed&.display_title || source_name
  end

  # The edition for `locale`, if one was declared.
  def variant_for(locale)
    target = locale.to_s
    variants.detect { |variant| variant.locale.to_s == target }
  end

  # The edition with no language yet: the one created when the clipping was
  # marked, before the summary detected the article's language.
  def source_variant
    variants.detect { |variant| variant.locale.blank? }
  end

  # The edition the clipping "is": the one in the detected language, falling back
  # to the not-yet-detected source and then to any edition.
  def primary_variant
    variant_for(language) || source_variant || variants.first
  end

  # The languages the story is actually published in — only pt-BR, only en-US,
  # or both. A translation with no URL of its own does not count: the story has
  # no edition in that language, only a translated rendering of another one.
  def languages
    LANGUAGES.select { |locale| variant_for(locale)&.url.present? }
  end

  # The edition the edit form shows for `locale`: the declared one, or the
  # language-less source under the first locale while the language is unknown.
  def stored_variant(locale)
    variant_for(locale) ||
      (source_variant if locale.to_s == (language.presence || LANGUAGES.first))
  end

  # The title to show in `locale`: that language's edition, falling back to the
  # primary one while the edition is missing.
  def title_for(locale)
    variant_for(locale)&.title.presence || primary_variant&.title
  end

  # The summary is language-specific, so it never falls back to another
  # language's text.
  def summary_for(locale)
    variant_for(locale)&.summary.presence
  end

  # The URL to send a reader of `locale` to: their edition's own URL when the
  # story has one, otherwise the primary edition's.
  def url_for(locale)
    variant_for(locale)&.url.presence || primary_variant&.url
  end

  def display_title
    primary_variant&.title
  end

  # Stores one generation result: the detected language, the translated title and
  # the summary in each language. A variant the reader wrote or corrected by hand
  # is left untouched; the source edition is moved to the detected language. The
  # URL is never written here, so a published edition keeps its own address and a
  # regeneration cannot overwrite one.
  def apply_summary(result)
    self.language = result.language

    source = adopt_source_variant(result)
    source.summary = result.summary_for(result.language) unless source.manual?

    other = SupportedLanguages.other(result.language)
    apply_translation(result, other) if other

    self.summary_status = :summarized
    self.summary_error = nil
  end

  private

  # The edition that holds the original title: the one already in the detected
  # language, otherwise the language-less source, otherwise a new one.
  def adopt_source_variant(result)
    existing = variant_for(result.language)
    return existing if existing

    source = source_variant
    return source.tap { |variant| variant.locale = result.language } if source

    variants.build(locale: result.language, url: primary_variant&.url, title: result.title_translated)
  end

  # Fills the edition for the other language — the model's translated title and
  # the summary in that language. Skips a manual edition, so a run never
  # overwrites what a person wrote, and never touches the URL, so a translation
  # without a page of its own falls back to the source edition's URL.
  def apply_translation(result, locale)
    variant = variant_for(locale)
    return if variant&.manual?

    variant ||= variants.build(locale: locale)
    variant.origin = :generated
    variant.title = result.title_translated
    variant.summary = result.summary_for(locale)
  end

  # A story is only meaningful with at least one language edition behind it.
  def has_a_variant
    errors.add(:variants, :blank) if variants.reject(&:marked_for_destruction?).empty?
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
  # that duplicates something already queued from a feed. Any edition's URL
  # counts, so the same story in another language is still a duplicate.
  def url_not_already_queued
    urls = variants.map { |variant| variant.url.presence&.downcase }.compact
    return if urls.empty?

    scope = Clipping.unsent.joins(:variants).where("lower(clipping_variants.url) IN (?)", urls)
    scope = scope.where.not(id: id) if id

    errors.add(:base, :duplicate_url) if scope.exists?
  end

  def enqueue_summary_generation
    GenerateSummaryJob.perform_later(id)
  end
end
