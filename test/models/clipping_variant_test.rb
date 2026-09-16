require "test_helper"

class ClippingVariantTest < ActiveSupport::TestCase
  test "is valid with a URL and a title" do
    variant = ClippingVariant.new(clipping: clippings(:pending), locale: "pt-BR",
                                 url: "https://example.com/a", title: "t")

    assert variant.valid?
  end

  test "requires a title" do
    variant = ClippingVariant.new(clipping: clippings(:pending))

    assert_not variant.valid?
    assert_includes variant.errors.attribute_names, :title
  end

  test "can exist without a URL" do
    variant = ClippingVariant.new(clipping: clippings(:pending), locale: "pt-BR", title: "t")

    assert variant.valid?
  end

  test "rejects a URL that is not http(s)" do
    variant = ClippingVariant.new(clipping: clippings(:pending), title: "t", url: "javascript:alert(1)")

    assert_not variant.valid?
    assert_includes variant.errors.attribute_names, :url
  end

  test "rejects a locale the site does not speak" do
    variant = ClippingVariant.new(clipping: clippings(:pending), locale: "de-DE",
                                 url: "https://example.com/a", title: "t")

    assert_not variant.valid?
    assert_includes variant.errors.attribute_names, :locale
  end

  test "can exist without a locale until the language is detected" do
    variant = ClippingVariant.new(clipping: clippings(:queued), url: "https://example.com/a", title: "t")

    assert variant.valid?
    assert_nil variant.locale
  end

  test "allows only one edition without a locale per clipping" do
    clipping = clippings(:pending) # already has a source edition without a locale

    variant = clipping.variants.build(url: "https://example.com/a", title: "t")

    assert_not variant.valid?
    assert_includes variant.errors.attribute_names, :locale
  end

  test "defaults to generated" do
    variant = ClippingVariant.new

    assert variant.generated?
  end
end
