require "rails_helper"

RSpec.describe BadgeComponent, type: :component do
  describe "variants" do
    it "renders with default variant when none specified" do
      render_inline(described_class.new) { "Default" }

      expect(page).to have_css("span.bg-slate-200.text-slate-800", text: "Default")
      expect(page).to have_css("span.dark\\:bg-slate-700.dark\\:text-slate-300")
    end

    it "renders default variant explicitly" do
      render_inline(described_class.new(variant: :default)) { "Default" }

      expect(page).to have_css("span.bg-slate-200.text-slate-800", text: "Default")
      expect(page).to have_css("span.dark\\:bg-slate-700.dark\\:text-slate-300")
    end

    it "renders success variant with green classes" do
      render_inline(described_class.new(variant: :success)) { "Success" }

      expect(page).to have_css("span.bg-green-200.text-green-800", text: "Success")
      expect(page).to have_css("span.ring-1.ring-inset.ring-green-600\\/20")
      expect(page).to have_css("span.dark\\:bg-green-900\\/30.dark\\:text-green-400.dark\\:ring-green-400\\/20")
    end

    it "renders warning variant with yellow classes" do
      render_inline(described_class.new(variant: :warning)) { "Warning" }

      expect(page).to have_css("span.bg-yellow-200.text-yellow-800", text: "Warning")
      expect(page).to have_css("span.ring-1.ring-inset.ring-yellow-600\\/20")
      expect(page).to have_css("span.dark\\:bg-yellow-900\\/30.dark\\:text-yellow-400.dark\\:ring-yellow-400\\/20")
    end

    it "renders danger variant with red classes" do
      render_inline(described_class.new(variant: :danger)) { "Danger" }

      expect(page).to have_css("span.bg-red-200.text-red-800", text: "Danger")
      expect(page).to have_css("span.ring-1.ring-inset.ring-red-600\\/20")
      expect(page).to have_css("span.dark\\:bg-red-900\\/30.dark\\:text-red-400.dark\\:ring-red-400\\/20")
    end

    it "renders info variant with blue classes" do
      render_inline(described_class.new(variant: :info)) { "Info" }

      expect(page).to have_css("span.bg-blue-200.text-blue-800", text: "Info")
      expect(page).to have_css("span.ring-1.ring-inset.ring-blue-600\\/20")
      expect(page).to have_css("span.dark\\:bg-blue-900\\/30.dark\\:text-blue-400.dark\\:ring-blue-400\\/20")
    end

    it "renders accent variant with amber classes" do
      render_inline(described_class.new(variant: :accent)) { "Accent" }

      expect(page).to have_css("span.bg-amber-200.text-amber-800", text: "Accent")
      expect(page).to have_css("span.ring-1.ring-inset.ring-amber-600\\/20")
      expect(page).to have_css("span.dark\\:bg-amber-900\\/30.dark\\:text-amber-400.dark\\:ring-amber-400\\/20")
    end

    it "raises ArgumentError for unknown variant" do
      expect {
        render_inline(described_class.new(variant: :bogus)) { "x" }
      }.to raise_error(ArgumentError, /variant/)
    end
  end

  describe "common classes" do
    it "always includes layout, shape, padding, typography classes" do
      render_inline(described_class.new) { "Tag" }

      %w[
        inline-flex
        items-center
        rounded-full
        px-2.5
        py-1
        text-sm
        font-medium
      ].each do |klass|
        expect(page).to have_css("span.#{klass.gsub('.', '\\.')}")
      end
    end
  end

  describe "icon option" do
    it "renders with icon before content and applies gap-1.5" do
      render_inline(described_class.new(variant: :success, icon: "check")) { "Done" }

      expect(page).to have_css("span.gap-1\\.5", text: "Done")
      expect(page).to have_css("span svg.w-3\\.5.h-3\\.5")

      # Icon precedes text: the SVG should appear before the trailing text node.
      html = page.native.to_html
      svg_index = html.index("<svg")
      text_index = html.index("Done")
      expect(svg_index).not_to be_nil
      expect(text_index).not_to be_nil
      expect(svg_index).to be < text_index
    end

    it "renders without icon by default" do
      render_inline(described_class.new(variant: :info)) { "Plain" }

      expect(page).not_to have_css("span svg")
      expect(page).not_to have_css("span.gap-1\\.5")
    end
  end

  describe "content" do
    it "renders content from block" do
      render_inline(described_class.new(variant: :info)) { "Docker Image" }

      expect(page).to have_css("span", text: "Docker Image")
    end
  end
end
