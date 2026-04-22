require "rails_helper"

RSpec.describe ButtonComponent, type: :component do
  describe "variants" do
    it "renders primary variant with brand blue classes" do
      render_inline(described_class.new(variant: :primary)) { "Save" }

      expect(page).to have_css("button.bg-blue-600.hover\\:bg-blue-700.text-white", text: "Save")
      expect(page).to have_css("button.dark\\:bg-blue-500.dark\\:hover\\:bg-blue-400")
    end

    it "renders secondary variant with slate classes" do
      render_inline(described_class.new(variant: :secondary)) { "Cancel" }

      expect(page).to have_css("button.bg-slate-100.hover\\:bg-slate-200.text-slate-700", text: "Cancel")
      expect(page).to have_css("button.dark\\:bg-slate-700.dark\\:hover\\:bg-slate-600.dark\\:text-slate-200")
    end

    it "renders outline variant with bordered classes" do
      render_inline(described_class.new(variant: :outline)) { "Outline" }

      expect(page).to have_css("button.border.border-slate-200.hover\\:bg-slate-50.text-slate-700", text: "Outline")
      expect(page).to have_css("button.dark\\:border-slate-600.dark\\:hover\\:bg-slate-700.dark\\:text-slate-200")
    end

    it "renders danger variant with red classes" do
      render_inline(described_class.new(variant: :danger)) { "Delete" }

      expect(page).to have_css("button.bg-red-600.hover\\:bg-red-700.text-white", text: "Delete")
      expect(page).to have_css("button.dark\\:bg-red-500.dark\\:hover\\:bg-red-400")
    end

    it "renders ghost variant with hover-only background" do
      render_inline(described_class.new(variant: :ghost)) { "Ghost" }

      expect(page).to have_css("button.hover\\:bg-slate-100.text-slate-600", text: "Ghost")
      expect(page).to have_css("button.dark\\:hover\\:bg-slate-700.dark\\:text-slate-300")
    end

    it "renders link variant with underline on hover" do
      render_inline(described_class.new(variant: :link)) { "Link" }

      expect(page).to have_css("button.text-blue-600.hover\\:text-blue-700.underline-offset-4.hover\\:underline", text: "Link")
      expect(page).to have_css("button.dark\\:text-blue-400.dark\\:hover\\:text-blue-300")
    end

    it "raises ArgumentError for unknown variant" do
      expect {
        render_inline(described_class.new(variant: :bogus)) { "x" }
      }.to raise_error(ArgumentError, /variant/)
    end
  end

  describe "sizes" do
    it "renders sm size with h-8" do
      render_inline(described_class.new(size: :sm)) { "Small" }

      expect(page).to have_css("button.h-8.px-3.text-sm", text: "Small")
    end

    it "renders md size with h-10" do
      render_inline(described_class.new(size: :md)) { "Medium" }

      expect(page).to have_css("button.h-10.px-4.text-base", text: "Medium")
    end

    it "renders lg size with h-12" do
      render_inline(described_class.new(size: :lg)) { "Large" }

      expect(page).to have_css("button.h-12.px-6.text-base", text: "Large")
    end

    it "raises ArgumentError for unknown size" do
      expect {
        render_inline(described_class.new(size: :huge)) { "x" }
      }.to raise_error(ArgumentError, /size/)
    end
  end

  describe "common classes" do
    it "always includes layout, typography, transition and focus classes" do
      render_inline(described_class.new) { "Go" }

      %w[
        inline-flex
        items-center
        justify-center
        font-medium
        rounded-md
        transition-colors
        duration-150
      ].each do |klass|
        expect(page).to have_css("button.#{klass}")
      end

      # Focus ring (escape : in Tailwind arbitrary values for CSS selector)
      expect(page).to have_css(
        "button.focus-visible\\:ring-2.focus-visible\\:ring-blue-500\\/50.focus-visible\\:ring-offset-2"
      )
      expect(page).to have_css(
        "button.dark\\:focus-visible\\:ring-blue-400\\/50.dark\\:focus-visible\\:ring-offset-slate-900"
      )
    end
  end

  describe "disabled state" do
    it "adds opacity/cursor/pointer-events classes and disabled attribute on button" do
      render_inline(described_class.new(disabled: true)) { "Off" }

      expect(page).to have_css("button.opacity-50.cursor-not-allowed.pointer-events-none", text: "Off")
      expect(page).to have_css("button[disabled]")
    end

    it "does not apply disabled classes when not disabled" do
      render_inline(described_class.new) { "On" }

      expect(page).not_to have_css("button.opacity-50")
      expect(page).not_to have_css("button[disabled]")
    end

    it "adds aria-disabled on link variant when disabled" do
      render_inline(described_class.new(href: "/x", disabled: true)) { "Nope" }

      expect(page).to have_css("a.opacity-50.cursor-not-allowed.pointer-events-none", text: "Nope")
      expect(page).to have_css("a[aria-disabled='true']")
    end
  end

  describe "icon option" do
    it "renders a heroicon before the text with gap-2 spacing" do
      render_inline(described_class.new(variant: :primary, icon: "check")) { "Save" }

      expect(page).to have_css("button.gap-2", text: "Save")
      # heroicon helper produces <svg> output
      expect(page).to have_css("button svg")
    end

    it "uses w-4 h-4 icon size for sm buttons" do
      render_inline(described_class.new(size: :sm, icon: "check")) { "Tiny" }

      expect(page).to have_css("button svg.w-4.h-4")
    end

    it "uses w-5 h-5 icon size for md buttons" do
      render_inline(described_class.new(size: :md, icon: "check")) { "Medium" }

      expect(page).to have_css("button svg.w-5.h-5")
    end

    it "uses w-5 h-5 icon size for lg buttons" do
      render_inline(described_class.new(size: :lg, icon: "check")) { "Large" }

      expect(page).to have_css("button svg.w-5.h-5")
    end

    it "does not apply gap-2 when there is no icon" do
      render_inline(described_class.new(variant: :primary)) { "Plain" }

      expect(page).not_to have_css("button.gap-2")
    end
  end

  describe "submit mode" do
    it "renders a <button type='submit'> when type: :submit is passed" do
      render_inline(described_class.new(type: :submit)) { "Submit" }

      expect(page).to have_css("button[type='submit']", text: "Submit")
    end

    it "defaults to type='button' when no type is given" do
      render_inline(described_class.new) { "Default" }

      expect(page).to have_css("button[type='button']", text: "Default")
    end
  end

  describe "link mode" do
    it "renders an <a> with href when href: is provided" do
      render_inline(described_class.new(variant: :outline, href: "/repositories")) { "Go" }

      expect(page).to have_css("a[href='/repositories']", text: "Go")
      expect(page).to have_css("a.border.border-slate-200")
    end

    it "does not render a type attribute on the anchor" do
      render_inline(described_class.new(href: "/x")) { "Go" }

      expect(page).not_to have_css("a[type]")
    end

    it "raises ArgumentError when both href: and type: are provided" do
      expect {
        described_class.new(href: "/x", type: :submit)
      }.to raise_error(ArgumentError, /href.*type|type.*href/)
    end
  end

  describe "icon-only usage" do
    it "renders with an aria-label and no text content" do
      render_inline(described_class.new(variant: :ghost, icon: "x-mark", "aria-label": "Close"))

      expect(page).to have_css("button[aria-label='Close']")
      expect(page).to have_css("button svg")
    end
  end
end
