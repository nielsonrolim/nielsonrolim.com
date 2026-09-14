require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "requires a name" do
    assert_not Category.new(name: nil).valid?
    assert_not Category.new(name: "   ").valid?
  end

  test "name is unique regardless of case" do
    Category.create!(name: "Rustlang")
    duplicate = Category.new(name: "rustlang")

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :name
  end

  test "find_or_create_by_name reuses an existing category, ignoring case and spacing" do
    existing = Category.find_or_create_by_name("Rustlang")

    assert_equal existing, Category.find_or_create_by_name("rustlang")
    assert_equal existing, Category.find_or_create_by_name("  RUSTLANG  ")
    assert_equal 1, Category.where("lower(name) = 'rustlang'").count
  end

  test "find_or_create_by_name creates a missing category, trimmed" do
    assert_difference -> { Category.count }, 1 do
      category = Category.find_or_create_by_name("  Novidade  ")

      assert_equal "Novidade", category.name
    end
  end

  test "find_or_create_by_name returns nil for a blank name" do
    assert_nil Category.find_or_create_by_name("   ")
    assert_nil Category.find_or_create_by_name(nil)
  end

  test "alphabetical is case-insensitive" do
    Category.create!(name: "zeta")
    Category.create!(name: "Alpha")

    assert_equal "Alpha", Category.alphabetical.first.name
  end

  test "removing a category removes its joins but keeps the feeds" do
    category = categories(:news)

    assert_difference -> { FeedCategory.count }, -category.feed_categories.count do
      assert_no_difference -> { Feed.count } do
        category.destroy
      end
    end
  end
end
