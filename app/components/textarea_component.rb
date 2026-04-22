# frozen_string_literal: true

# TextareaComponent renders brand-consistent multi-line text inputs per DESIGN.md section 3.3.
#
# Mirrors InputComponent's label/error/help_text/required pattern.
# Key difference: textareas have NO size token (no `h-*`) — they're multi-line
# and size vertically via the `rows:` attribute, combined with `py-2.5 resize-y`.
# Error takes precedence over help text when both are set.
#
# Usage:
#   <%= render TextareaComponent.new(name: "bio", label: "Bio", rows: 4) %>
#   <%= render TextareaComponent.new(name: "notes", placeholder: "Your notes…", rows: 6) %>
#   <%= render TextareaComponent.new(name: "bio", label: "Bio", required: true) %>
#   <%= render TextareaComponent.new(name: "bio", error: "Bio can't be blank") %>
#   <%= render TextareaComponent.new(name: "bio", help_text: "Short biography") %>
class TextareaComponent < ViewComponent::Base
  BASE_CLASSES = "w-full rounded-md border border-slate-200 dark:border-slate-600 " \
                 "bg-white dark:bg-slate-700 px-3 py-2.5 text-sm " \
                 "text-slate-900 dark:text-slate-100 " \
                 "placeholder:text-slate-400 dark:placeholder:text-slate-500 " \
                 "focus:outline-none focus:ring-2 focus:ring-blue-500/20 dark:focus:ring-blue-400/20 " \
                 "focus:border-blue-500 dark:focus:border-blue-400 " \
                 "transition-colors duration-150 resize-y"

  ERROR_CLASSES = "border-red-500 focus:ring-red-500/20 focus:border-red-500"

  LABEL_CLASSES = "block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5"

  REQUIRED_MARK_CLASSES = "text-red-500 ml-0.5"

  ERROR_MESSAGE_CLASSES = "text-sm text-red-600 dark:text-red-400 mt-1.5"

  HELP_TEXT_CLASSES = "text-sm text-slate-500 dark:text-slate-400 mt-1.5"

  def initialize(name:, value: nil, rows: 4, label: nil, placeholder: nil,
                 required: false, error: nil, help_text: nil, id: nil, **html_options)
    @name = name
    @value = value
    @rows = rows
    @label = label
    @placeholder = placeholder
    @required = required
    @error = error
    @help_text = help_text
    @id = id
    @html_options = html_options
  end

  def textarea_id
    @id || "textarea_#{@name}"
  end

  def error_id
    "#{textarea_id}_error"
  end

  def help_id
    "#{textarea_id}_help"
  end

  def error?
    !@error.nil?
  end

  def help_text?
    !@help_text.nil? && !error?
  end

  def css_classes
    [
      BASE_CLASSES,
      (error? ? ERROR_CLASSES : nil)
    ].compact.join(" ")
  end

  def textarea_attrs
    attrs = @html_options.merge(
      name: @name,
      id: textarea_id,
      rows: @rows,
      class: css_classes
    )
    attrs[:placeholder] = @placeholder unless @placeholder.nil?
    attrs[:required] = true if @required
    if error?
      attrs[:"aria-invalid"] = "true"
      attrs[:"aria-describedby"] = error_id
    elsif help_text?
      attrs[:"aria-describedby"] = help_id
    end
    attrs
  end

  attr_reader :value, :label, :required, :error, :help_text
end
