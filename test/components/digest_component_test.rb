require "test_helper"
require "view_component/test_case"

class DigestComponentTest < ViewComponent::TestCase
  def full
    @full ||= "sha256:1d1ddb624e47aabbccddeeff00112233445566778899aabbccddeeff00112233"
  end

  # display text

  test "renders the first 12 characters of the hex portion of the digest" do
    render_inline(DigestComponent.new(digest: full))

    assert_text "1d1ddb624e47"
    assert_no_text "sha256:"
  end

  # clipboard wiring

  test "attaches the clipboard Stimulus controller with the full digest as the copy value" do
    render_inline(DigestComponent.new(digest: full))

    assert_selector "[data-controller='clipboard'][data-clipboard-text-value='#{full}']"
  end

  # copy button

  test "renders a button that triggers clipboard#copy" do
    render_inline(DigestComponent.new(digest: full))

    assert_selector "button[data-action='click->clipboard#copy']"
  end

  test "gives the button an accessible label naming the digest" do
    render_inline(DigestComponent.new(digest: full))

    assert_selector "button[aria-label='Copy digest 1d1ddb624e47']"
  end

  test "marks the inner svg as the clipboard icon target for success-state swapping" do
    render_inline(DigestComponent.new(digest: full))

    assert_selector "button svg[data-clipboard-target='icon']"
  end

  # edge cases

  test "renders an empty short and no copy button when digest is blank" do
    render_inline(DigestComponent.new(digest: ""))

    assert_no_selector "button[data-action='click->clipboard#copy']"
  end

  test "renders an empty short and no copy button when digest is nil" do
    render_inline(DigestComponent.new(digest: nil))

    assert_no_selector "button[data-action='click->clipboard#copy']"
  end
end
