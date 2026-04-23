require "test_helper"
require "view_component/test_case"

class ButtonComponentTest < ViewComponent::TestCase
  # variants

  test "renders primary variant with brand blue classes" do
    render_inline(ButtonComponent.new(variant: :primary)) { "Save" }

    assert_selector "button.bg-blue-600.hover\\:bg-blue-700.text-white", text: "Save"
    assert_selector "button.dark\\:bg-blue-500.dark\\:hover\\:bg-blue-400"
  end

  test "renders secondary variant with slate classes" do
    render_inline(ButtonComponent.new(variant: :secondary)) { "Cancel" }

    assert_selector "button.bg-slate-100.hover\\:bg-slate-200.text-slate-700", text: "Cancel"
    assert_selector "button.dark\\:bg-slate-700.dark\\:hover\\:bg-slate-600.dark\\:text-slate-200"
  end

  test "renders outline variant with bordered classes" do
    render_inline(ButtonComponent.new(variant: :outline)) { "Outline" }

    assert_selector "button.border.border-slate-200.hover\\:bg-slate-50.text-slate-700", text: "Outline"
    assert_selector "button.dark\\:border-slate-600.dark\\:hover\\:bg-slate-700.dark\\:text-slate-200"
  end

  test "renders danger variant with red classes" do
    render_inline(ButtonComponent.new(variant: :danger)) { "Delete" }

    assert_selector "button.bg-red-600.hover\\:bg-red-700.text-white", text: "Delete"
    assert_selector "button.dark\\:bg-red-500.dark\\:hover\\:bg-red-400"
  end

  test "renders ghost variant with hover-only background" do
    render_inline(ButtonComponent.new(variant: :ghost)) { "Ghost" }

    assert_selector "button.hover\\:bg-slate-100.text-slate-600", text: "Ghost"
    assert_selector "button.dark\\:hover\\:bg-slate-700.dark\\:text-slate-300"
  end

  test "renders link variant with underline on hover" do
    render_inline(ButtonComponent.new(variant: :link)) { "Link" }

    assert_selector "button.text-blue-600.hover\\:text-blue-700.underline-offset-4.hover\\:underline", text: "Link"
    assert_selector "button.dark\\:text-blue-400.dark\\:hover\\:text-blue-300"
  end

  test "raises ArgumentError for unknown variant" do
    err = assert_raises(ArgumentError) {
      render_inline(ButtonComponent.new(variant: :bogus)) { "x" }
    }
    assert_match(/variant/, err.message)
  end

  # sizes

  test "renders sm size with h-8" do
    render_inline(ButtonComponent.new(size: :sm)) { "Small" }

    assert_selector "button.h-8.px-3.text-sm", text: "Small"
  end

  test "renders md size with h-10" do
    render_inline(ButtonComponent.new(size: :md)) { "Medium" }

    assert_selector "button.h-10.px-4.text-base", text: "Medium"
  end

  test "renders lg size with h-12" do
    render_inline(ButtonComponent.new(size: :lg)) { "Large" }

    assert_selector "button.h-12.px-6.text-base", text: "Large"
  end

  test "raises ArgumentError for unknown size" do
    err = assert_raises(ArgumentError) {
      render_inline(ButtonComponent.new(size: :huge)) { "x" }
    }
    assert_match(/size/, err.message)
  end

  # common classes

  test "always includes layout, typography, transition and focus classes" do
    render_inline(ButtonComponent.new) { "Go" }

    %w[
      inline-flex
      items-center
      justify-center
      font-medium
      rounded-md
      transition-colors
      duration-150
    ].each do |klass|
      assert_selector "button.#{klass}"
    end

    assert_selector "button.focus-visible\\:ring-2.focus-visible\\:ring-blue-500\\/50.focus-visible\\:ring-offset-2"
    assert_selector "button.dark\\:focus-visible\\:ring-blue-400\\/50.dark\\:focus-visible\\:ring-offset-slate-900"
  end

  # disabled state

  test "adds opacity/cursor/pointer-events classes and disabled attribute on button" do
    render_inline(ButtonComponent.new(disabled: true)) { "Off" }

    assert_selector "button.opacity-50.cursor-not-allowed.pointer-events-none", text: "Off"
    assert_selector "button[disabled]"
  end

  test "does not apply disabled classes when not disabled" do
    render_inline(ButtonComponent.new) { "On" }

    assert_no_selector "button.opacity-50"
    assert_no_selector "button[disabled]"
  end

  test "adds aria-disabled on link variant when disabled" do
    render_inline(ButtonComponent.new(href: "/x", disabled: true)) { "Nope" }

    assert_selector "a.opacity-50.cursor-not-allowed.pointer-events-none", text: "Nope"
    assert_selector "a[aria-disabled='true']"
  end

  # icon option

  test "renders a heroicon before the text with gap-2 spacing" do
    render_inline(ButtonComponent.new(variant: :primary, icon: "check")) { "Save" }

    assert_selector "button.gap-2", text: "Save"
    assert_selector "button svg"
  end

  test "uses w-4 h-4 icon size for sm buttons" do
    render_inline(ButtonComponent.new(size: :sm, icon: "check")) { "Tiny" }

    assert_selector "button svg.w-4.h-4"
  end

  test "uses w-5 h-5 icon size for md buttons" do
    render_inline(ButtonComponent.new(size: :md, icon: "check")) { "Medium" }

    assert_selector "button svg.w-5.h-5"
  end

  test "uses w-5 h-5 icon size for lg buttons" do
    render_inline(ButtonComponent.new(size: :lg, icon: "check")) { "Large" }

    assert_selector "button svg.w-5.h-5"
  end

  test "does not apply gap-2 when there is no icon" do
    render_inline(ButtonComponent.new(variant: :primary)) { "Plain" }

    assert_no_selector "button.gap-2"
  end

  # submit mode

  test "renders a <button type='submit'> when type: :submit is passed" do
    render_inline(ButtonComponent.new(type: :submit)) { "Submit" }

    assert_selector "button[type='submit']", text: "Submit"
  end

  test "defaults to type='button' when no type is given" do
    render_inline(ButtonComponent.new) { "Default" }

    assert_selector "button[type='button']", text: "Default"
  end

  # link mode

  test "renders an <a> with href when href: is provided" do
    render_inline(ButtonComponent.new(variant: :outline, href: "/repositories")) { "Go" }

    assert_selector "a[href='/repositories']", text: "Go"
    assert_selector "a.border.border-slate-200"
  end

  test "does not render a type attribute on the anchor" do
    render_inline(ButtonComponent.new(href: "/x")) { "Go" }

    assert_no_selector "a[type]"
  end

  test "raises ArgumentError when both href: and type: are provided" do
    err = assert_raises(ArgumentError) {
      ButtonComponent.new(href: "/x", type: :submit)
    }
    assert_match(/href.*type|type.*href/, err.message)
  end

  # icon-only usage

  test "renders with an aria-label and no text content" do
    render_inline(ButtonComponent.new(variant: :ghost, icon: "x-mark", "aria-label": "Close"))

    assert_selector "button[aria-label='Close']"
    assert_selector "button svg"
  end
end
