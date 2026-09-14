class Category < ApplicationRecord
  has_many :feed_categories, dependent: :destroy
  has_many :feeds, through: :feed_categories

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  scope :alphabetical, -> { order(Arel.sql("lower(name)")) }

  # Category names are typed by hand, so "Ruby", "ruby" and " ruby " must resolve
  # to the same record. The unique index on lower(name) is the backstop against
  # two requests creating it at once.
  def self.find_or_create_by_name(raw_name)
    name = raw_name.to_s.strip
    return nil if name.blank?

    find_by("lower(name) = ?", name.downcase) || begin
      create!(name: name)
    rescue ActiveRecord::RecordNotUnique
      find_by!("lower(name) = ?", name.downcase)
    end
  end
end
