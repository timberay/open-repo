require "rails_helper"

RSpec.describe TextareaComponent, type: :component do
  describe "defaults" do
    it "renders textarea" do
      render_inline(described_class.new(name: "bio"))

      expect(page).to have_css("textarea[name='bio']")
    end

    it "auto-generates id from name when not provided" do
      render_inline(described_class.new(name: "bio"))

      expect(page).to have_css("textarea#textarea_bio[name='bio']")
    end

    it "uses provided id when given" do
      render_inline(described_class.new(name: "bio", id: "custom_id"))

      expect(page).to have_css("textarea#custom_id")
    end
  end

  describe "rows" do
    it "defaults rows to 4" do
      render_inline(described_class.new(name: "bio"))

      expect(page).to have_css("textarea[rows='4']")
    end

    it "respects custom rows:" do
      render_inline(described_class.new(name: "notes", rows: 8))

      expect(page).to have_css("textarea[rows='8']")
    end
  end

  describe "value" do
    it "renders value in textarea content" do
      render_inline(described_class.new(name: "description", value: "Hello world"))

      expect(page).to have_css("textarea", text: "Hello world")
    end

    it "renders no content when value is nil" do
      render_inline(described_class.new(name: "description"))

      expect(page).to have_css("textarea", text: "")
    end
  end

  describe "label" do
    it "renders label when provided" do
      render_inline(described_class.new(name: "bio", label: "Bio"))

      expect(page).to have_css("label[for='textarea_bio']", text: "Bio")
      expect(page).to have_css(
        "label.block.text-sm.font-medium.text-slate-700.dark\\:text-slate-300.mb-1\\.5"
      )
    end

    it "does not render label when omitted" do
      render_inline(described_class.new(name: "bio"))

      expect(page).not_to have_css("label")
    end

    it "renders required asterisk and adds required attribute" do
      render_inline(described_class.new(name: "bio", label: "Bio", required: true))

      expect(page).to have_css("label span.text-red-500.ml-0\\.5", text: "*")
      expect(page).to have_css("textarea[required]")
    end

    it "does not render asterisk when not required" do
      render_inline(described_class.new(name: "bio", label: "Bio"))

      expect(page).not_to have_css("label span.text-red-500")
      expect(page).not_to have_css("textarea[required]")
    end
  end

  describe "error state" do
    it "renders error and applies error classes" do
      render_inline(described_class.new(name: "bio", error: "Bio can't be blank"))

      expect(page).to have_css(
        "textarea.border-red-500.focus\\:ring-red-500\\/20.focus\\:border-red-500"
      )
      expect(page).to have_css("textarea[aria-invalid='true']")
      expect(page).to have_css("textarea[aria-describedby='textarea_bio_error']")
      expect(page).to have_css(
        "p#textarea_bio_error.text-sm.text-red-600.dark\\:text-red-400.mt-1\\.5",
        text: "Bio can't be blank"
      )
    end

    it "does not apply error classes when no error" do
      render_inline(described_class.new(name: "bio"))

      expect(page).not_to have_css("textarea.border-red-500")
      expect(page).not_to have_css("textarea[aria-invalid]")
      expect(page).not_to have_css("p[id$='_error']")
    end
  end

  describe "help_text" do
    it "renders help_text when provided" do
      render_inline(described_class.new(name: "bio", help_text: "Short biography, 1-2 paragraphs"))

      expect(page).to have_css(
        "p#textarea_bio_help.text-sm.text-slate-500.dark\\:text-slate-400.mt-1\\.5",
        text: "Short biography, 1-2 paragraphs"
      )
      expect(page).to have_css("textarea[aria-describedby='textarea_bio_help']")
    end

    it "hides help_text when error present" do
      render_inline(described_class.new(name: "bio", help_text: "Tell us more", error: "Too short"))

      expect(page).not_to have_css("p[id$='_help']")
      expect(page).to have_css("p#textarea_bio_error", text: "Too short")
      expect(page).to have_css("textarea[aria-describedby='textarea_bio_error']")
    end
  end

  describe "base classes" do
    it "applies py-2.5 resize-y base classes" do
      render_inline(described_class.new(name: "bio"))

      expect(page).to have_css("textarea.py-2\\.5")
      expect(page).to have_css("textarea.resize-y")
    end

    it "does NOT include any h-* height class" do
      render_inline(described_class.new(name: "bio"))

      textarea = page.find("textarea")
      classes = textarea[:class].to_s.split(/\s+/)
      height_classes = classes.grep(/\Ah-\S+\z/)
      expect(height_classes).to be_empty, "expected no h-* classes, found: #{height_classes.inspect}"
    end

    it "includes shared layout, border, focus, and transition classes" do
      render_inline(described_class.new(name: "bio"))

      %w[
        w-full
        rounded-md
        border
        border-slate-200
        bg-white
        px-3
        text-sm
        text-slate-900
        transition-colors
        duration-150
      ].each do |klass|
        expect(page).to have_css("textarea.#{klass}")
      end

      expect(page).to have_css(
        "textarea.focus\\:outline-none.focus\\:ring-2.focus\\:ring-blue-500\\/20.focus\\:border-blue-500"
      )
      expect(page).to have_css(
        "textarea.dark\\:border-slate-600.dark\\:bg-slate-700.dark\\:text-slate-100"
      )
      expect(page).to have_css(
        "textarea.placeholder\\:text-slate-400.dark\\:placeholder\\:text-slate-500"
      )
    end
  end

  describe "html_options passthrough" do
    it "passes through placeholder and other html_options" do
      render_inline(
        described_class.new(
          name: "bio",
          placeholder: "Your notes…",
          autocomplete: "off",
          data: { testid: "bio-textarea" }
        )
      )

      expect(page).to have_css("textarea[placeholder='Your notes…']")
      expect(page).to have_css("textarea[autocomplete='off']")
      expect(page).to have_css("textarea[data-testid='bio-textarea']")
    end
  end
end
