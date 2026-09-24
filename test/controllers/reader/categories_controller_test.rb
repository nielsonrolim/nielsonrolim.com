require "test_helper"

class Reader::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as_admin
  end

  teardown do
    sign_out
  end

  test "lists the categories with their feed counts" do
    get reader_categories_path

    assert_response :success
    assert_select "input[value=?]", "Ruby"
    assert_select "input[value=?]", "News"
    assert_select "input[value=?]", "Web"
    assert_select "body", /1 fonte/
  end

  test "a category with several feeds counts them all" do
    # ruby_blog carries both Ruby and Web, so each of those counts one feed.
    # Give Web a second feed to prove the count aggregates.
    feeds(:hacker_news).categories << categories(:web)

    get reader_categories_path

    assert_select "body", /2 fontes/
  end

  test "creating a new category" do
    assert_difference -> { Category.count }, 1 do
      post reader_categories_path, params: { category: { name: "Rust" } }
    end

    assert_redirected_to reader_categories_path
    assert_includes Category.pluck(:name), "Rust"
  end

  test "creating an existing category reuses it and does not duplicate" do
    assert_no_difference -> { Category.count } do
      post reader_categories_path, params: { category: { name: "ruby" } }
    end

    assert_redirected_to reader_categories_path
  end

  test "creating without a name does not create anything" do
    assert_no_difference -> { Category.count } do
      post reader_categories_path, params: { category: { name: "   " } }
    end

    assert_redirected_to reader_categories_path
  end

  test "renaming a category keeps its feeds" do
    category = categories(:web)

    patch reader_category_path(category), params: { category: { name: "Frontend" } }

    assert_redirected_to reader_categories_path
    assert_equal "Frontend", category.reload.name
    assert_equal [ feeds(:ruby_blog).id ], category.feeds.pluck(:id)
  end

  test "renaming to a blank name does not save" do
    category = categories(:web)

    patch reader_category_path(category), params: { category: { name: "" } }

    assert_redirected_to reader_categories_path
    assert_equal "Web", category.reload.name
  end

  test "renaming to a name already taken does not save" do
    category = categories(:web)

    patch reader_category_path(category), params: { category: { name: "ruby" } }

    assert_redirected_to reader_categories_path
    assert_equal "Web", category.reload.name
  end

  test "removing a category unlinks its feeds but keeps them" do
    category = categories(:ruby)

    assert_difference -> { Category.count }, -1 do
      assert_no_difference -> { Feed.count } do
        delete reader_category_path(category)
      end
    end

    assert_redirected_to reader_categories_path
    assert_equal [ "Web" ], feeds(:ruby_blog).reload.categories.map(&:name)
  end

  test "the reader subnav links to the categories page" do
    get reader_categories_path

    assert_select "a[href=?]", reader_categories_path
  end

  test "the confirmation names how many feeds will lose the category" do
    get reader_categories_path

    # Podcasts has a single feed, so the message uses the singular.
    assert_select "button[data-confirm*=?]", "A 1 fonte continua"
  end

  test "requires a session" do
    sign_out

    get reader_categories_path

    assert_response :redirect
  end
end
