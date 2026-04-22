require "rails_helper"

RSpec.describe InputComponent, type: :component do
  describe "defaults" do
    it "renders input with text type by default" do
      render_inline(described_class.new(name: "title"))

      expect(page).to have_css("input[type='text'][name='title']")
    end

    it "auto-generates id from name when not provided" do
      render_inline(described_class.new(name: "email"))

      expect(page).to have_css("input#input_email[name='email']")
    end

    it "uses provided id when given" do
      render_inline(described_class.new(name: "email", id: "custom_id"))

      expect(page).to have_css("input#custom_id")
    end
  end

  describe "label" do
    it "renders label when provided" do
      render_inline(described_class.new(name: "email", label: "Email"))

      expect(page).to have_css("label[for='input_email']", text: "Email")
      expect(page).to have_css(
        "label.block.text-sm.font-medium.text-slate-700.dark\\:text-slate-300.mb-1\\.5"
      )
    end

    it "does not render label when omitted" do
      render_inline(described_class.new(name: "email"))

      expect(page).not_to have_css("label")
    end

    it "renders required asterisk when required: true" do
      render_inline(described_class.new(name: "email", label: "Email", required: true))

      expect(page).to have_css("label span.text-red-500.ml-0\\.5", text: "*")
      expect(page).to have_css("input[required]")
    end

    it "does not render asterisk when not required" do
      render_inline(described_class.new(name: "email", label: "Email"))

      expect(page).not_to have_css("label span.text-red-500")
      expect(page).not_to have_css("input[required]")
    end
  end

  describe "types" do
    it "renders a text input when type: :text" do
      render_inline(described_class.new(name: "title", type: :text))

      expect(page).to have_css("input[type='text']")
    end

    it "renders an email input when type: :email" do
      render_inline(described_class.new(name: "email", type: :email))

      expect(page).to have_css("input[type='email']")
    end

    it "renders a password input when type: :password" do
      render_inline(described_class.new(name: "password", type: :password))

      expect(page).to have_css("input[type='password']")
    end

    it "renders a search input when type: :search" do
      render_inline(described_class.new(name: "q", type: :search))

      expect(page).to have_css("input[type='search']")
    end

    it "raises ArgumentError on unknown type" do
      expect {
        described_class.new(name: "x", type: :number)
      }.to raise_error(ArgumentError, /type/)
    end
  end

  describe "sizes" do
    it "renders sm size with h-8" do
      render_inline(described_class.new(name: "q", size: :sm))

      expect(page).to have_css("input.h-8")
    end

    it "renders md size with h-10" do
      render_inline(described_class.new(name: "q", size: :md))

      expect(page).to have_css("input.h-10")
    end

    it "renders lg size with h-12" do
      render_inline(described_class.new(name: "q", size: :lg))

      expect(page).to have_css("input.h-12")
    end

    it "raises ArgumentError on unknown size" do
      expect {
        described_class.new(name: "x", size: :huge)
      }.to raise_error(ArgumentError, /size/)
    end
  end

  describe "base classes" do
    it "always includes layout, border, focus, and transition classes" do
      render_inline(described_class.new(name: "q"))

      %w[
        w-full
        rounded-md
        border
        border-slate-200
        bg-white
        px-3
        py-2
        text-sm
        text-slate-900
        transition-colors
        duration-150
      ].each do |klass|
        expect(page).to have_css("input.#{klass}")
      end

      expect(page).to have_css(
        "input.focus\\:outline-none.focus\\:ring-2.focus\\:ring-blue-500\\/20.focus\\:border-blue-500"
      )
      expect(page).to have_css(
        "input.dark\\:border-slate-600.dark\\:bg-slate-700.dark\\:text-slate-100"
      )
      expect(page).to have_css(
        "input.placeholder\\:text-slate-400.dark\\:placeholder\\:text-slate-500"
      )
    end
  end

  describe "error state" do
    it "renders error message and applies error state classes" do
      render_inline(described_class.new(name: "title", error: "Title can't be blank"))

      expect(page).to have_css("input.border-red-500.focus\\:ring-red-500\\/20.focus\\:border-red-500")
      expect(page).to have_css("input[aria-invalid='true']")
      expect(page).to have_css("input[aria-describedby='input_title_error']")
      expect(page).to have_css(
        "p#input_title_error.text-sm.text-red-600.dark\\:text-red-400.mt-1\\.5",
        text: "Title can't be blank"
      )
    end

    it "does not apply error classes when no error" do
      render_inline(described_class.new(name: "title"))

      expect(page).not_to have_css("input.border-red-500")
      expect(page).not_to have_css("input[aria-invalid]")
      expect(page).not_to have_css("p[id$='_error']")
    end
  end

  describe "help_text" do
    it "renders help_text when provided" do
      render_inline(described_class.new(name: "bio", help_text: "1-2 sentences about yourself"))

      expect(page).to have_css(
        "p#input_bio_help.text-sm.text-slate-500.dark\\:text-slate-400.mt-1\\.5",
        text: "1-2 sentences about yourself"
      )
    end

    it "uses aria-describedby to link help text" do
      render_inline(described_class.new(name: "bio", help_text: "Tell us more"))

      expect(page).to have_css("input[aria-describedby='input_bio_help']")
    end

    it "hides help_text when error is present (error takes precedence)" do
      render_inline(described_class.new(name: "bio", help_text: "Tell us more", error: "Too short"))

      expect(page).not_to have_css("p[id$='_help']")
      expect(page).to have_css("p#input_bio_error", text: "Too short")
      expect(page).to have_css("input[aria-describedby='input_bio_error']")
    end
  end

  describe "html_options passthrough" do
    it "passes through value, placeholder, and other html_options" do
      render_inline(
        described_class.new(
          name: "email",
          value: "hello@example.com",
          placeholder: "you@example.com",
          autocomplete: "email",
          data: { testid: "email-input" }
        )
      )

      expect(page).to have_css("input[value='hello@example.com']")
      expect(page).to have_css("input[placeholder='you@example.com']")
      expect(page).to have_css("input[autocomplete='email']")
      expect(page).to have_css("input[data-testid='email-input']")
    end
  end
end
