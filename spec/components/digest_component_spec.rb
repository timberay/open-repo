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
end
