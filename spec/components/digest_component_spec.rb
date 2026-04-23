require "rails_helper"

RSpec.describe DigestComponent, type: :component do
  let(:full) { "sha256:1d1ddb624e47aabbccddeeff00112233445566778899aabbccddeeff00112233" }

  describe "display text" do
    it "renders the first 12 characters of the hex portion of the digest" do
      render_inline(described_class.new(digest: full))

      expect(page).to have_text("1d1ddb624e47")
      expect(page).not_to have_text("sha256:")
    end
  end

  describe "clipboard wiring" do
    it "attaches the clipboard Stimulus controller with the full digest as the copy value" do
      render_inline(described_class.new(digest: full))

      expect(page).to have_css(
        "[data-controller='clipboard'][data-clipboard-text-value='#{full}']"
      )
    end
  end

  describe "copy button" do
    before { render_inline(described_class.new(digest: full)) }

    it "renders a button that triggers clipboard#copy" do
      expect(page).to have_css("button[data-action='click->clipboard#copy']")
    end

    it "gives the button an accessible label naming the digest" do
      expect(page).to have_css("button[aria-label='Copy digest 1d1ddb624e47']")
    end

    it "marks the inner svg as the clipboard icon target for success-state swapping" do
      expect(page).to have_css("button svg[data-clipboard-target='icon']")
    end
  end

  describe "edge cases" do
    it "renders an empty short and no copy button when digest is blank" do
      render_inline(described_class.new(digest: ""))

      expect(page).not_to have_css("button[data-action='click->clipboard#copy']")
    end

    it "renders an empty short and no copy button when digest is nil" do
      render_inline(described_class.new(digest: nil))

      expect(page).not_to have_css("button[data-action='click->clipboard#copy']")
    end
  end
end
