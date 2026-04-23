require "test_helper"
require "view_component/test_case"

class CardComponentTest < ViewComponent::TestCase
  # basic card

  test "renders basic card with body content" do
    render_inline(CardComponent.new) { "Body content" }

    assert_selector "div.rounded-lg.bg-white.border.border-slate-200.shadow-sm", text: "Body content"
    assert_selector "div.dark\\:bg-slate-800.dark\\:border-slate-700"
  end

  test "renders content from block" do
    render_inline(CardComponent.new) { "Hello world" }

    assert_text "Hello world"
  end

  # header slot

  test "renders header slot when provided" do
    render_inline(CardComponent.new) do |card|
      card.with_header { "Header text" }
      "Body"
    end

    assert_selector "div.px-6.py-4.border-b.border-slate-200", text: "Header text"
    assert_selector "div.dark\\:border-slate-700"
  end

  test "does not render header div when header slot not provided" do
    render_inline(CardComponent.new) { "Body only" }

    assert_no_selector "div.border-b"
  end

  test "passes through rich header content via html" do
    render_inline(CardComponent.new) do |card|
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

    assert_selector "h3.text-lg.font-semibold.text-slate-900", text: "Title"
    assert_selector "p.text-sm.text-slate-600.mt-1", text: "Subtitle"
  end

  # footer slot

  test "renders footer slot when provided" do
    render_inline(CardComponent.new) do |card|
      card.with_footer { "Footer actions" }
      "Body"
    end

    assert_selector "div.px-6.py-4.border-t.border-slate-100.bg-slate-50\\/50", text: "Footer actions"
    assert_selector "div.dark\\:border-slate-700.dark\\:bg-slate-800\\/50"
  end

  test "does not render footer div when footer slot not provided" do
    render_inline(CardComponent.new) { "Body only" }

    assert_no_selector "div.border-t"
  end

  # header and footer together

  test "renders both header and footer" do
    render_inline(CardComponent.new) do |card|
      card.with_header { "Header" }
      card.with_footer { "Footer" }
      "Body"
    end

    assert_selector "div.border-b", text: "Header"
    assert_selector "div.border-t", text: "Footer"
    assert_text "Body"
  end

  # padding option

  test "applies default body padding" do
    render_inline(CardComponent.new) { "Body" }

    assert_selector "div.px-6.py-4", text: "Body"
  end

  test "accepts padding: :default explicitly" do
    render_inline(CardComponent.new(padding: :default)) { "Body" }

    assert_selector "div.px-6.py-4", text: "Body"
  end

  test "omits body padding when padding: :none" do
    render_inline(CardComponent.new(padding: :none)) { "Embedded" }

    body_html = page.native.to_html
    assert_includes body_html, "Embedded"
    assert_no_selector "div.px-6.py-4", text: "Embedded"
  end

  test "raises ArgumentError for unknown padding" do
    err = assert_raises(ArgumentError) {
      CardComponent.new(padding: :massive)
    }
    assert_match(/padding/, err.message)
  end

  # html_options passthrough

  test "merges additional classes with base classes on the wrapper" do
    render_inline(CardComponent.new(class: "hover:shadow-md transition-shadow duration-150")) { "Body" }

    assert_selector "div.rounded-lg.bg-white.border.border-slate-200.shadow-sm"
    assert_selector "div.rounded-lg.hover\\:shadow-md.transition-shadow.duration-150"
  end

  test "passes through data attributes to the outer wrapper" do
    render_inline(CardComponent.new(data: { controller: "card" })) { "Body" }

    assert_selector "div.rounded-lg[data-controller='card']"
  end

  test "passes through id attribute to the outer wrapper" do
    render_inline(CardComponent.new(id: "repo-card")) { "Body" }

    assert_selector "div#repo-card.rounded-lg"
  end
end
