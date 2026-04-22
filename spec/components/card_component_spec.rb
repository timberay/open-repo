require "rails_helper"

RSpec.describe CardComponent, type: :component do
  describe "basic card" do
    it "renders basic card with body content" do
      render_inline(described_class.new) { "Body content" }

      expect(page).to have_css(
        "div.rounded-lg.bg-white.border.border-slate-200.shadow-sm",
        text: "Body content"
      )
      expect(page).to have_css("div.dark\\:bg-slate-800.dark\\:border-slate-700")
    end

    it "renders content from block" do
      render_inline(described_class.new) { "Hello world" }

      expect(page).to have_text("Hello world")
    end
  end

  describe "header slot" do
    it "renders header slot when provided" do
      render_inline(described_class.new) do |card|
        card.with_header { "Header text" }
        "Body"
      end

      expect(page).to have_css(
        "div.px-6.py-4.border-b.border-slate-200",
        text: "Header text"
      )
      expect(page).to have_css("div.dark\\:border-slate-700")
    end

    it "does not render header div when header slot not provided" do
      render_inline(described_class.new) { "Body only" }

      expect(page).not_to have_css("div.border-b")
    end

    it "passes through rich header content via html" do
      render_inline(described_class.new) do |card|
        card.with_header do
          # rubocop:disable Rails/OutputSafety
          (
            '<h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">Title</h3>' \
            '<p class="text-sm text-slate-600 dark:text-slate-400 mt-1">Subtitle</p>'
          ).html_safe
          # rubocop:enable Rails/OutputSafety
        end
        "Body"
      end

      expect(page).to have_css("h3.text-lg.font-semibold.text-slate-900", text: "Title")
      expect(page).to have_css("p.text-sm.text-slate-600.mt-1", text: "Subtitle")
    end
  end

  describe "footer slot" do
    it "renders footer slot when provided" do
      render_inline(described_class.new) do |card|
        card.with_footer { "Footer actions" }
        "Body"
      end

      expect(page).to have_css(
        "div.px-6.py-4.border-t.border-slate-100.bg-slate-50\\/50",
        text: "Footer actions"
      )
      expect(page).to have_css("div.dark\\:border-slate-700.dark\\:bg-slate-800\\/50")
    end

    it "does not render footer div when footer slot not provided" do
      render_inline(described_class.new) { "Body only" }

      expect(page).not_to have_css("div.border-t")
    end
  end

  describe "header and footer together" do
    it "renders both header and footer" do
      render_inline(described_class.new) do |card|
        card.with_header { "Header" }
        card.with_footer { "Footer" }
        "Body"
      end

      expect(page).to have_css("div.border-b", text: "Header")
      expect(page).to have_css("div.border-t", text: "Footer")
      expect(page).to have_text("Body")
    end
  end

  describe "padding option" do
    it "applies default body padding" do
      render_inline(described_class.new) { "Body" }

      expect(page).to have_css("div.px-6.py-4", text: "Body")
    end

    it "accepts padding: :default explicitly" do
      render_inline(described_class.new(padding: :default)) { "Body" }

      expect(page).to have_css("div.px-6.py-4", text: "Body")
    end

    it "omits body padding when padding: :none" do
      render_inline(described_class.new(padding: :none)) { "Embedded" }

      # The body div exists and holds the content, but has no padding utilities.
      body_html = page.native.to_html
      # Body div is the innermost wrapper containing "Embedded" — it should not
      # carry any px-* or py-* classes.
      expect(body_html).to include("Embedded")
      # The outer wrapper has rounded-lg etc.; the inner content div should have
      # an empty class attribute (or none).
      expect(page).not_to have_css("div.px-6.py-4", text: "Embedded")
    end

    it "raises ArgumentError for unknown padding" do
      expect {
        described_class.new(padding: :massive)
      }.to raise_error(ArgumentError, /padding/)
    end
  end
end
