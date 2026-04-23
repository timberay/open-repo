require "test_helper"
require "view_component/test_case"

class SelectComponentTest < ViewComponent::TestCase
  def roles
    @roles ||= [ [ "User", "user" ], [ "Admin", "admin" ], [ "Guest", "guest" ] ]
  end

  # defaults

  test "renders select with options" do
    render_inline(SelectComponent.new(name: "role", options: roles))

    assert_selector "select[name='role']"
    assert_selector "select option[value='user']", text: "User"
    assert_selector "select option[value='admin']", text: "Admin"
    assert_selector "select option[value='guest']", text: "Guest"
  end

  test "auto-generates id from name when not provided" do
    render_inline(SelectComponent.new(name: "role", options: roles))

    assert_selector "select#select_role[name='role']"
  end

  test "uses provided id when given" do
    render_inline(SelectComponent.new(name: "role", options: roles, id: "custom_id"))

    assert_selector "select#custom_id"
  end

  # selected

  test "marks selected option via selected:" do
    render_inline(SelectComponent.new(name: "role", options: roles, selected: "admin"))

    assert_selector "select option[value='admin'][selected]", text: "Admin"
    assert_no_selector "select option[value='user'][selected]"
    assert_no_selector "select option[value='guest'][selected]"
  end

  # prompt

  test "renders prompt when prompt: provided and selects it by default when no selected:" do
    render_inline(SelectComponent.new(name: "role", options: roles, prompt: "— select —"))

    assert_selector "select option[value=''][disabled][selected]", text: "— select —"
  end

  test "does not select the prompt when a selected: value is provided" do
    render_inline(
      SelectComponent.new(name: "role", options: roles, prompt: "— select —", selected: "admin")
    )

    assert_selector "select option[value=''][disabled]", text: "— select —"
    assert_no_selector "select option[value=''][selected]"
    assert_selector "select option[value='admin'][selected]"
  end

  # label

  test "renders label when provided" do
    render_inline(SelectComponent.new(name: "role", options: roles, label: "Role"))

    assert_selector "label[for='select_role']", text: "Role"
    assert_selector "label.block.text-sm.font-medium.text-slate-700.dark\\:text-slate-300.mb-1\\.5"
  end

  test "does not render label when omitted" do
    render_inline(SelectComponent.new(name: "role", options: roles))

    assert_no_selector "label"
  end

  test "renders required attribute and asterisk when required: true" do
    render_inline(
      SelectComponent.new(name: "role", options: roles, label: "Role", required: true)
    )

    assert_selector "label span.text-red-500.ml-0\\.5", text: "*"
    assert_selector "select[required]"
  end

  test "does not render asterisk when not required" do
    render_inline(SelectComponent.new(name: "role", options: roles, label: "Role"))

    assert_no_selector "label span.text-red-500"
    assert_no_selector "select[required]"
  end

  # sizes

  test "renders sm size with h-8" do
    render_inline(SelectComponent.new(name: "role", options: roles, size: :sm))

    assert_selector "select.h-8"
  end

  test "renders md size with h-10" do
    render_inline(SelectComponent.new(name: "role", options: roles, size: :md))

    assert_selector "select.h-10"
  end

  test "renders lg size with h-12" do
    render_inline(SelectComponent.new(name: "role", options: roles, size: :lg))

    assert_selector "select.h-12"
  end

  test "raises ArgumentError on unknown size" do
    err = assert_raises(ArgumentError) {
      SelectComponent.new(name: "role", options: roles, size: :huge)
    }
    assert_match(/size/, err.message)
  end

  # base classes

  test "always includes layout, border, focus, and transition classes" do
    render_inline(SelectComponent.new(name: "role", options: roles))

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
      assert_selector "select.#{klass}"
    end

    assert_selector "select.focus\\:outline-none.focus\\:ring-2.focus\\:ring-blue-500\\/20.focus\\:border-blue-500"
    assert_selector "select.dark\\:border-slate-600.dark\\:bg-slate-700.dark\\:text-slate-100"
  end

  # error state

  test "renders error and applies error classes" do
    render_inline(
      SelectComponent.new(name: "role", options: roles, error: "Please choose one")
    )

    assert_selector "select.border-red-500.focus\\:ring-red-500\\/20.focus\\:border-red-500"
    assert_selector "select[aria-invalid='true']"
    assert_selector "select[aria-describedby='select_role_error']"
    assert_selector(
      "p#select_role_error.text-sm.text-red-600.dark\\:text-red-400.mt-1\\.5",
      text: "Please choose one"
    )
  end

  test "does not apply error classes when no error" do
    render_inline(SelectComponent.new(name: "role", options: roles))

    assert_no_selector "select.border-red-500"
    assert_no_selector "select[aria-invalid]"
    assert_no_selector "p[id$='_error']"
  end

  # help_text

  test "renders help_text when provided" do
    render_inline(
      SelectComponent.new(name: "role", options: roles, help_text: "Assign a role")
    )

    assert_selector(
      "p#select_role_help.text-sm.text-slate-500.dark\\:text-slate-400.mt-1\\.5",
      text: "Assign a role"
    )
    assert_selector "select[aria-describedby='select_role_help']"
  end

  test "hides help_text when error is present and only references error via aria-describedby" do
    render_inline(
      SelectComponent.new(
        name: "role", options: roles,
        help_text: "Assign a role", error: "Please choose one"
      )
    )

    assert_no_selector "p[id$='_help']"
    assert_selector "p#select_role_error", text: "Please choose one"
    assert_selector "select[aria-describedby='select_role_error']"
  end

  # validation

  test "raises ArgumentError on unknown size (validation section)" do
    err = assert_raises(ArgumentError) {
      SelectComponent.new(name: "role", options: roles, size: :xxl)
    }
    assert_match(/size/, err.message)
  end

  test "raises ArgumentError on malformed options (not array of pairs)" do
    err1 = assert_raises(ArgumentError) {
      SelectComponent.new(name: "role", options: [ [ "User", "user" ], "admin" ])
    }
    assert_match(/options/, err1.message)

    err2 = assert_raises(ArgumentError) {
      SelectComponent.new(name: "role", options: [ [ "User" ] ])
    }
    assert_match(/options/, err2.message)

    err3 = assert_raises(ArgumentError) {
      SelectComponent.new(name: "role", options: "nope")
    }
    assert_match(/options/, err3.message)
  end

  # html_options passthrough

  test "passes through arbitrary html options" do
    render_inline(
      SelectComponent.new(
        name: "role",
        options: roles,
        autocomplete: "off",
        data: { testid: "role-select" }
      )
    )

    assert_selector "select[autocomplete='off']"
    assert_selector "select[data-testid='role-select']"
  end
end
