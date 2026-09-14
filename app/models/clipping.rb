class Clipping < ApplicationRecord
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
  validate :entry_not_already_queued

  scope :unsent, -> { where(newsletter_id: nil) }
  scope :queued, -> { unsent.order(:created_at) }

  after_create_commit :enqueue_summary_generation

  private

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
