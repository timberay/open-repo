require "test_helper"
require "view_component/test_case"

class TextareaComponentTest < ViewComponent::TestCase
  # defaults

  test "renders textarea" do
    render_inline(TextareaComponent.new(name: "bio"))

    assert_selector "textarea[name='bio']"
  end

  test "auto-generates id from name when not provided" do
    render_inline(TextareaComponent.new(name: "bio"))

    assert_selector "textarea#textarea_bio[name='bio']"
  end

  test "uses provided id when given" do
    render_inline(TextareaComponent.new(name: "bio", id: "custom_id"))

    assert_selector "textarea#custom_id"
  end

  # rows

  test "defaults rows to 4" do
    render_inline(TextareaComponent.new(name: "bio"))

    assert_selector "textarea[rows='4']"
  end

  test "respects custom rows:" do
    render_inline(TextareaComponent.new(name: "notes", rows: 8))

    assert_selector "textarea[rows='8']"
  end

  # value

  test "renders value in textarea content" do
    render_inline(TextareaComponent.new(name: "description", value: "Hello world"))

    assert_selector "textarea", text: "Hello world"
  end

  test "renders no content when value is nil" do
    render_inline(TextareaComponent.new(name: "description"))

    assert_selector "textarea", text: ""
  end

  # label

  test "renders label when provided" do
    render_inline(TextareaComponent.new(name: "bio", label: "Bio"))

    assert_selector "label[for='textarea_bio']", text: "Bio"
    assert_selector "label.block.text-sm.font-medium.text-slate-700.dark\\:text-slate-300.mb-1\\.5"
  end

  test "does not render label when omitted" do
    render_inline(TextareaComponent.new(name: "bio"))

    assert_no_selector "label"
  end

  test "renders required asterisk and adds required attribute" do
    render_inline(TextareaComponent.new(name: "bio", label: "Bio", required: true))

    assert_selector "label span.text-red-500.ml-0\\.5", text: "*"
    assert_selector "textarea[required]"
  end

  test "does not render asterisk when not required" do
    render_inline(TextareaComponent.new(name: "bio", label: "Bio"))

    assert_no_selector "label span.text-red-500"
    assert_no_selector "textarea[required]"
  end

  # error state

  test "renders error and applies error classes" do
    render_inline(TextareaComponent.new(name: "bio", error: "Bio can't be blank"))

    assert_selector "textarea.border-red-500.focus\\:ring-red-500\\/20.focus\\:border-red-500"
    assert_selector "textarea[aria-invalid='true']"
    assert_selector "textarea[aria-describedby='textarea_bio_error']"
    assert_selector(
      "p#textarea_bio_error.text-sm.text-red-600.dark\\:text-red-400.mt-1\\.5",
      text: "Bio can't be blank"
    )
  end

  test "does not apply error classes when no error" do
    render_inline(TextareaComponent.new(name: "bio"))

    assert_no_selector "textarea.border-red-500"
    assert_no_selector "textarea[aria-invalid]"
    assert_no_selector "p[id$='_error']"
  end

  # help_text

  test "renders help_text when provided" do
    render_inline(TextareaComponent.new(name: "bio", help_text: "Short biography, 1-2 paragraphs"))

    assert_selector(
      "p#textarea_bio_help.text-sm.text-slate-500.dark\\:text-slate-400.mt-1\\.5",
      text: "Short biography, 1-2 paragraphs"
    )
    assert_selector "textarea[aria-describedby='textarea_bio_help']"
  end

  test "hides help_text when error present" do
    render_inline(TextareaComponent.new(name: "bio", help_text: "Tell us more", error: "Too short"))

    assert_no_selector "p[id$='_help']"
    assert_selector "p#textarea_bio_error", text: "Too short"
    assert_selector "textarea[aria-describedby='textarea_bio_error']"
  end

  # base classes

  test "applies py-2.5 resize-y base classes" do
    render_inline(TextareaComponent.new(name: "bio"))

    assert_selector "textarea.py-2\\.5"
    assert_selector "textarea.resize-y"
  end

  test "does NOT include any h-* height class" do
    render_inline(TextareaComponent.new(name: "bio"))

    textarea = page.find("textarea")
    classes = textarea[:class].to_s.split(/\s+/)
    height_classes = classes.grep(/\Ah-\S+\z/)
    assert height_classes.empty?, "expected no h-* classes, found: #{height_classes.inspect}"
  end

  test "includes shared layout, border, focus, and transition classes" do
    render_inline(TextareaComponent.new(name: "bio"))

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
      assert_selector "textarea.#{klass}"
    end

    assert_selector "textarea.focus\\:outline-none.focus\\:ring-2.focus\\:ring-blue-500\\/20.focus\\:border-blue-500"
    assert_selector "textarea.dark\\:border-slate-600.dark\\:bg-slate-700.dark\\:text-slate-100"
    assert_selector "textarea.placeholder\\:text-slate-400.dark\\:placeholder\\:text-slate-500"
  end

  # html_options passthrough

  test "passes through placeholder and other html_options" do
    render_inline(
      TextareaComponent.new(
        name: "bio",
        placeholder: "Your notes…",
        autocomplete: "off",
        data: { testid: "bio-textarea" }
      )
    )

    assert_selector "textarea[placeholder='Your notes…']"
    assert_selector "textarea[autocomplete='off']"
    assert_selector "textarea[data-testid='bio-textarea']"
  end
end
