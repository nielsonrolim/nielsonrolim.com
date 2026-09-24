module Reader
  # Category management. Categories are created on the fly while editing a feed
  # (see Reader::FeedsController#resolved_category_ids); this page is the place
  # to see them all, rename a typo and remove one that is no longer useful.
  #
  # Deleting a category only drops its joins — the feeds themselves stay put,
  # possibly uncategorised — which is Category#dependent: :destroy on the joins.
  class CategoriesController < BaseController
    def index
      @categories = Category.alphabetical
      @feed_counts = FeedCategory.group(:category_id).count
      @category = Category.new
    end

    def create
      name = create_params[:name]
      category = Category.find_or_create_by_name(name)

      if category.nil?
        redirect_to reader_categories_path, alert: t("reader.categories.create.invalid"), status: :see_other
      elsif category.previously_new_record?
        redirect_to reader_categories_path, notice: t("reader.categories.create.success", name: category.name),
                    status: :see_other
      else
        redirect_to reader_categories_path, notice: t("reader.categories.create.exists", name: category.name),
                    status: :see_other
      end
    end

    def update
      @category = Category.find(params[:id])

      if @category.update(update_params)
        redirect_to reader_categories_path, notice: t("reader.categories.update.success", name: @category.name),
                    status: :see_other
      else
        redirect_to reader_categories_path,
                    alert: t("reader.categories.update.invalid", error: @category.errors.full_messages.to_sentence),
                    status: :see_other
      end
    end

    # Removing a category unlinks its feeds and keeps them: the confirmation
    # spells out how many are about to be uncategorised.
    def destroy
      category = Category.find(params[:id])
      name = category.name
      category.destroy

      redirect_to reader_categories_path, notice: t("reader.categories.destroy.success", name: name), status: :see_other
    end

    private

    def create_params
      params.require(:category).permit(:name)
    end

    def update_params
      params.require(:category).permit(:name)
    end
  end
end
