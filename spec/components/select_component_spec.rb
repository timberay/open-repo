require "rails_helper"

RSpec.describe SelectComponent, type: :component do
  let(:roles) { [ [ "User", "user" ], [ "Admin", "admin" ], [ "Guest", "guest" ] ] }

  describe "defaults" do
    it "renders select with options" do
      render_inline(described_class.new(name: "role", options: roles))

      expect(page).to have_css("select[name='role']")
      expect(page).to have_css("select option[value='user']", text: "User")
      expect(page).to have_css("select option[value='admin']", text: "Admin")
      expect(page).to have_css("select option[value='guest']", text: "Guest")
    end

    it "auto-generates id from name when not provided" do
      render_inline(described_class.new(name: "role", options: roles))

      expect(page).to have_css("select#select_role[name='role']")
    end

    it "uses provided id when given" do
      render_inline(described_class.new(name: "role", options: roles, id: "custom_id"))

      expect(page).to have_css("select#custom_id")
    end
  end

  describe "selected" do
    it "marks selected option via selected:" do
      render_inline(described_class.new(name: "role", options: roles, selected: "admin"))

      expect(page).to have_css("select option[value='admin'][selected]", text: "Admin")
      expect(page).not_to have_css("select option[value='user'][selected]")
      expect(page).not_to have_css("select option[value='guest'][selected]")
    end
  end

  describe "prompt" do
    it "renders prompt when prompt: provided and selects it by default when no selected:" do
      render_inline(described_class.new(name: "role", options: roles, prompt: "— select —"))

      expect(page).to have_css("select option[value=''][disabled][selected]", text: "— select —")
    end

    it "does not select the prompt when a selected: value is provided" do
      render_inline(
        described_class.new(name: "role", options: roles, prompt: "— select —", selected: "admin")
      )

      expect(page).to have_css("select option[value=''][disabled]", text: "— select —")
      expect(page).not_to have_css("select option[value=''][selected]")
      expect(page).to have_css("select option[value='admin'][selected]")
    end
  end

  describe "label" do
    it "renders label when provided" do
      render_inline(described_class.new(name: "role", options: roles, label: "Role"))

      expect(page).to have_css("label[for='select_role']", text: "Role")
      expect(page).to have_css(
        "label.block.text-sm.font-medium.text-slate-700.dark\\:text-slate-300.mb-1\\.5"
      )
    end

    it "does not render label when omitted" do
      render_inline(described_class.new(name: "role", options: roles))

      expect(page).not_to have_css("label")
    end

    it "renders required attribute and asterisk when required: true" do
      render_inline(
        described_class.new(name: "role", options: roles, label: "Role", required: true)
      )

      expect(page).to have_css("label span.text-red-500.ml-0\\.5", text: "*")
      expect(page).to have_css("select[required]")
    end

    it "does not render asterisk when not required" do
      render_inline(described_class.new(name: "role", options: roles, label: "Role"))

      expect(page).not_to have_css("label span.text-red-500")
      expect(page).not_to have_css("select[required]")
    end
  end

  describe "sizes" do
    it "renders sm size with h-8" do
      render_inline(described_class.new(name: "role", options: roles, size: :sm))

      expect(page).to have_css("select.h-8")
    end

    it "renders md size with h-10" do
      render_inline(described_class.new(name: "role", options: roles, size: :md))

      expect(page).to have_css("select.h-10")
    end

    it "renders lg size with h-12" do
      render_inline(described_class.new(name: "role", options: roles, size: :lg))

      expect(page).to have_css("select.h-12")
    end

    it "raises ArgumentError on unknown size" do
      expect {
        described_class.new(name: "role", options: roles, size: :huge)
      }.to raise_error(ArgumentError, /size/)
    end
  end

  describe "base classes" do
    it "always includes layout, border, focus, and transition classes" do
      render_inline(described_class.new(name: "role", options: roles))

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
        expect(page).to have_css("select.#{klass}")
      end

      expect(page).to have_css(
        "select.focus\\:outline-none.focus\\:ring-2.focus\\:ring-blue-500\\/20.focus\\:border-blue-500"
      )
      expect(page).to have_css(
        "select.dark\\:border-slate-600.dark\\:bg-slate-700.dark\\:text-slate-100"
      )
    end
  end

  describe "error state" do
    it "renders error and applies error classes" do
      render_inline(
        described_class.new(name: "role", options: roles, error: "Please choose one")
      )

      expect(page).to have_css(
        "select.border-red-500.focus\\:ring-red-500\\/20.focus\\:border-red-500"
      )
      expect(page).to have_css("select[aria-invalid='true']")
      expect(page).to have_css("select[aria-describedby='select_role_error']")
      expect(page).to have_css(
        "p#select_role_error.text-sm.text-red-600.dark\\:text-red-400.mt-1\\.5",
        text: "Please choose one"
      )
    end

    it "does not apply error classes when no error" do
      render_inline(described_class.new(name: "role", options: roles))

      expect(page).not_to have_css("select.border-red-500")
      expect(page).not_to have_css("select[aria-invalid]")
      expect(page).not_to have_css("p[id$='_error']")
    end
  end

  describe "help_text" do
    it "renders help_text when provided" do
      render_inline(
        described_class.new(name: "role", options: roles, help_text: "Assign a role")
      )

      expect(page).to have_css(
        "p#select_role_help.text-sm.text-slate-500.dark\\:text-slate-400.mt-1\\.5",
        text: "Assign a role"
      )
      expect(page).to have_css("select[aria-describedby='select_role_help']")
    end

    it "hides help_text when error is present and only references error via aria-describedby" do
      render_inline(
        described_class.new(
          name: "role", options: roles,
          help_text: "Assign a role", error: "Please choose one"
        )
      )

      expect(page).not_to have_css("p[id$='_help']")
      expect(page).to have_css("p#select_role_error", text: "Please choose one")
      expect(page).to have_css("select[aria-describedby='select_role_error']")
    end
  end

  describe "validation" do
    it "raises ArgumentError on unknown size" do
      expect {
        described_class.new(name: "role", options: roles, size: :xxl)
      }.to raise_error(ArgumentError, /size/)
    end

    it "raises ArgumentError on malformed options (not array of pairs)" do
      expect {
        described_class.new(name: "role", options: [ [ "User", "user" ], "admin" ])
      }.to raise_error(ArgumentError, /options/)

      expect {
        described_class.new(name: "role", options: [ [ "User" ] ])
      }.to raise_error(ArgumentError, /options/)

      expect {
        described_class.new(name: "role", options: "nope")
      }.to raise_error(ArgumentError, /options/)
    end
  end

  describe "html_options passthrough" do
    it "passes through arbitrary html options" do
      render_inline(
        described_class.new(
          name: "role",
          options: roles,
          autocomplete: "off",
          data: { testid: "role-select" }
        )
      )

      expect(page).to have_css("select[autocomplete='off']")
      expect(page).to have_css("select[data-testid='role-select']")
    end
  end
end
