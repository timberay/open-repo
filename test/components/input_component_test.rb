require "test_helper"
require "view_component/test_case"

class InputComponentTest < ViewComponent::TestCase
  # defaults

  test "renders input with text type by default" do
    render_inline(InputComponent.new(name: "title"))

    assert_selector "input[type='text'][name='title']"
  end

  test "auto-generates id from name when not provided" do
    render_inline(InputComponent.new(name: "email"))

    assert_selector "input#input_email[name='email']"
  end

  test "uses provided id when given" do
    render_inline(InputComponent.new(name: "email", id: "custom_id"))

    assert_selector "input#custom_id"
  end

  # label

  test "renders label when provided" do
    render_inline(InputComponent.new(name: "email", label: "Email"))

    assert_selector "label[for='input_email']", text: "Email"
    assert_selector "label.block.text-sm.font-medium.text-slate-700.dark\\:text-slate-300.mb-1\\.5"
  end

  test "does not render label when omitted" do
    render_inline(InputComponent.new(name: "email"))

    assert_no_selector "label"
  end

  test "renders required asterisk when required: true" do
    render_inline(InputComponent.new(name: "email", label: "Email", required: true))

    assert_selector "label span.text-red-500.ml-0\\.5", text: "*"
    assert_selector "input[required]"
  end

  test "does not render asterisk when not required" do
    render_inline(InputComponent.new(name: "email", label: "Email"))

    assert_no_selector "label span.text-red-500"
    assert_no_selector "input[required]"
  end

  # types

  test "renders a text input when type: :text" do
    render_inline(InputComponent.new(name: "title", type: :text))

    assert_selector "input[type='text']"
  end

  test "renders an email input when type: :email" do
    render_inline(InputComponent.new(name: "email", type: :email))

    assert_selector "input[type='email']"
  end

  test "renders a password input when type: :password" do
    render_inline(InputComponent.new(name: "password", type: :password))

    assert_selector "input[type='password']"
  end

  test "renders a search input when type: :search" do
    render_inline(InputComponent.new(name: "q", type: :search))

    assert_selector "input[type='search']"
  end

  test "raises ArgumentError on unknown type" do
    err = assert_raises(ArgumentError) {
      InputComponent.new(name: "x", type: :number)
    }
    assert_match(/type/, err.message)
  end

  # sizes

  test "renders sm size with h-8" do
    render_inline(InputComponent.new(name: "q", size: :sm))

    assert_selector "input.h-8"
  end

  test "renders md size with h-10" do
    render_inline(InputComponent.new(name: "q", size: :md))

    assert_selector "input.h-10"
  end

  test "renders lg size with h-12" do
    render_inline(InputComponent.new(name: "q", size: :lg))

    assert_selector "input.h-12"
  end

  test "raises ArgumentError on unknown size" do
    err = assert_raises(ArgumentError) {
      InputComponent.new(name: "x", size: :huge)
    }
    assert_match(/size/, err.message)
  end

  # base classes

  test "always includes layout, border, focus, and transition classes" do
    render_inline(InputComponent.new(name: "q"))

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
      assert_selector "input.#{klass}"
    end

    assert_selector "input.focus\\:outline-none.focus\\:ring-2.focus\\:ring-blue-500\\/20.focus\\:border-blue-500"
    assert_selector "input.dark\\:border-slate-600.dark\\:bg-slate-700.dark\\:text-slate-100"
    assert_selector "input.placeholder\\:text-slate-400.dark\\:placeholder\\:text-slate-500"
  end

  # error state

  test "renders error message and applies error state classes" do
    render_inline(InputComponent.new(name: "title", error: "Title can't be blank"))

    assert_selector "input.border-red-500.focus\\:ring-red-500\\/20.focus\\:border-red-500"
    assert_selector "input[aria-invalid='true']"
    assert_selector "input[aria-describedby='input_title_error']"
    assert_selector(
      "p#input_title_error.text-sm.text-red-600.dark\\:text-red-400.mt-1\\.5",
      text: "Title can't be blank"
    )
  end

  test "does not apply error classes when no error" do
    render_inline(InputComponent.new(name: "title"))

    assert_no_selector "input.border-red-500"
    assert_no_selector "input[aria-invalid]"
    assert_no_selector "p[id$='_error']"
  end

  # help_text

  test "renders help_text when provided" do
    render_inline(InputComponent.new(name: "bio", help_text: "1-2 sentences about yourself"))

    assert_selector(
      "p#input_bio_help.text-sm.text-slate-500.dark\\:text-slate-400.mt-1\\.5",
      text: "1-2 sentences about yourself"
    )
  end

  test "uses aria-describedby to link help text" do
    render_inline(InputComponent.new(name: "bio", help_text: "Tell us more"))

    assert_selector "input[aria-describedby='input_bio_help']"
  end

  test "hides help_text when error is present (error takes precedence)" do
    render_inline(InputComponent.new(name: "bio", help_text: "Tell us more", error: "Too short"))

    assert_no_selector "p[id$='_help']"
    assert_selector "p#input_bio_error", text: "Too short"
    assert_selector "input[aria-describedby='input_bio_error']"
  end

  # html_options passthrough

  test "passes through value, placeholder, and other html_options" do
    render_inline(
      InputComponent.new(
        name: "email",
        value: "hello@example.com",
        placeholder: "you@example.com",
        autocomplete: "email",
        data: { testid: "email-input" }
      )
    )

    assert_selector "input[value='hello@example.com']"
    assert_selector "input[placeholder='you@example.com']"
    assert_selector "input[autocomplete='email']"
    assert_selector "input[data-testid='email-input']"
  end
end
