require "test_helper"
require "view_component/test_case"

class BadgeComponentTest < ViewComponent::TestCase
  # variants

  test "renders with default variant when none specified" do
    render_inline(BadgeComponent.new) { "Default" }

    assert_selector "span.bg-slate-200.text-slate-800", text: "Default"
    assert_selector "span.dark\\:bg-slate-700.dark\\:text-slate-300"
  end

  test "renders default variant explicitly" do
    render_inline(BadgeComponent.new(variant: :default)) { "Default" }

    assert_selector "span.bg-slate-200.text-slate-800", text: "Default"
    assert_selector "span.dark\\:bg-slate-700.dark\\:text-slate-300"
  end

  test "renders success variant with green classes" do
    render_inline(BadgeComponent.new(variant: :success)) { "Success" }

    assert_selector "span.bg-green-200.text-green-800", text: "Success"
    assert_selector "span.ring-1.ring-inset.ring-green-600\\/20"
    assert_selector "span.dark\\:bg-green-900\\/30.dark\\:text-green-400.dark\\:ring-green-400\\/20"
  end

  test "renders warning variant with yellow classes" do
    render_inline(BadgeComponent.new(variant: :warning)) { "Warning" }

    assert_selector "span.bg-yellow-200.text-yellow-800", text: "Warning"
    assert_selector "span.ring-1.ring-inset.ring-yellow-600\\/20"
    assert_selector "span.dark\\:bg-yellow-900\\/30.dark\\:text-yellow-400.dark\\:ring-yellow-400\\/20"
  end

  test "renders danger variant with red classes" do
    render_inline(BadgeComponent.new(variant: :danger)) { "Danger" }

    assert_selector "span.bg-red-200.text-red-800", text: "Danger"
    assert_selector "span.ring-1.ring-inset.ring-red-600\\/20"
    assert_selector "span.dark\\:bg-red-900\\/30.dark\\:text-red-400.dark\\:ring-red-400\\/20"
  end

  test "renders info variant with blue classes" do
    render_inline(BadgeComponent.new(variant: :info)) { "Info" }

    assert_selector "span.bg-blue-200.text-blue-800", text: "Info"
    assert_selector "span.ring-1.ring-inset.ring-blue-600\\/20"
    assert_selector "span.dark\\:bg-blue-900\\/30.dark\\:text-blue-400.dark\\:ring-blue-400\\/20"
  end

  test "renders accent variant with amber classes" do
    render_inline(BadgeComponent.new(variant: :accent)) { "Accent" }

    assert_selector "span.bg-amber-200.text-amber-800", text: "Accent"
    assert_selector "span.ring-1.ring-inset.ring-amber-600\\/20"
    assert_selector "span.dark\\:bg-amber-900\\/30.dark\\:text-amber-400.dark\\:ring-amber-400\\/20"
  end

  test "raises ArgumentError for unknown variant" do
    err = assert_raises(ArgumentError) {
      render_inline(BadgeComponent.new(variant: :bogus)) { "x" }
    }
    assert_match(/variant/, err.message)
  end

  # common classes

  test "always includes layout, shape, padding, typography classes" do
    render_inline(BadgeComponent.new) { "Tag" }

    %w[
      inline-flex
      items-center
      rounded-full
      px-2.5
      py-1
      text-sm
      font-medium
    ].each do |klass|
      assert_selector "span.#{klass.gsub(".", "\\.")}"
    end
  end

  # icon option

  test "renders with icon before content and applies gap-1.5" do
    render_inline(BadgeComponent.new(variant: :success, icon: "check")) { "Done" }

    assert_selector "span.gap-1\\.5", text: "Done"
    assert_selector "span svg.w-3\\.5.h-3\\.5"

    html = page.native.to_html
    svg_index = html.index("<svg")
    text_index = html.index("Done")
    assert_not_nil svg_index
    assert_not_nil text_index
    assert svg_index < text_index
  end

  test "renders without icon by default" do
    render_inline(BadgeComponent.new(variant: :info)) { "Plain" }

    assert_no_selector "span svg"
    assert_no_selector "span.gap-1\\.5"
  end

  # content

  test "renders content from block" do
    render_inline(BadgeComponent.new(variant: :info)) { "Docker Image" }

    assert_selector "span", text: "Docker Image"
  end
end
