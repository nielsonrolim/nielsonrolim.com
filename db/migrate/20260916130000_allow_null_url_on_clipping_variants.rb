class AllowNullUrlOnClippingVariants < ActiveRecord::Migration[8.1]
  # The URL is the address of a published edition, not a per-language field. A
  # variant that only holds a machine translation has no page of its own, so the
  # URL is optional; readers of that language fall back to the edition that does
  # exist (see Clipping#url_for).
  def change
    change_column_null :clipping_variants, :url, true
  end
end
