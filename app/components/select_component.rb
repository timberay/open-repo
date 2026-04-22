# frozen_string_literal: true

# SelectComponent renders brand-consistent <select> controls per DESIGN.md 3.3.
#
# Matches InputComponent height tokens (h-8/h-10/h-12) so inline groupings
# (label + input + select) align per DESIGN.md 3.3 Inline Height Consistency
# Rule. Accepts an `options:` array of [label, value] pairs, optional prompt
# placeholder, selected value, label with required asterisk, error state
# with aria-describedby, and help text. Error takes precedence over help
# text when both are set.
#
# Usage:
#   roles = [["User", "user"], ["Admin", "admin"], ["Guest", "guest"]]
#   <%= render SelectComponent.new(name: "role", label: "Role", options: roles) %>
#   <%= render SelectComponent.new(name: "role", options: roles, selected: "admin") %>
#   <%= render SelectComponent.new(name: "role", options: roles, size: :sm,
#                                  required: true) %>
#   <%= render SelectComponent.new(name: "role", options: roles,
#                                  help_text: "Assign a role") %>
#   <%= render SelectComponent.new(name: "role", options: roles,
#                                  error: "Please choose one") %>
#   <%= render SelectComponent.new(name: "role", options: roles,
#                                  prompt: "— select —") %>
class SelectComponent < ViewComponent::Base
  SIZES = {
    sm: "h-8",
    md: "h-10",
    lg: "h-12"
  }.freeze

  BASE_CLASSES = "w-full rounded-md border border-slate-200 dark:border-slate-600 " \
                 "bg-white dark:bg-slate-700 px-3 py-2 text-sm " \
                 "text-slate-900 dark:text-slate-100 " \
                 "focus:outline-none focus:ring-2 focus:ring-blue-500/20 dark:focus:ring-blue-400/20 " \
                 "focus:border-blue-500 dark:focus:border-blue-400 " \
                 "transition-colors duration-150"

  ERROR_CLASSES = "border-red-500 focus:ring-red-500/20 focus:border-red-500"

  LABEL_CLASSES = "block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5"

  REQUIRED_MARK_CLASSES = "text-red-500 ml-0.5"

  ERROR_MESSAGE_CLASSES = "text-sm text-red-600 dark:text-red-400 mt-1.5"

  HELP_TEXT_CLASSES = "text-sm text-slate-500 dark:text-slate-400 mt-1.5"

  def initialize(name:, options:, selected: nil, size: :md, label: nil,
                 required: false, error: nil, help_text: nil, id: nil,
                 prompt: nil, **html_options)
    raise ArgumentError, "unknown size: #{size.inspect}" unless SIZES.key?(size)
    validate_options!(options)

    @name = name
    @options = options
    @selected = selected
    @size = size
    @label = label
    @required = required
    @error = error
    @help_text = help_text
    @id = id
    @prompt = prompt
    @html_options = html_options
  end

  def select_id
    @id || "select_#{@name}"
  end

  def error_id
    "#{select_id}_error"
  end

  def help_id
    "#{select_id}_help"
  end

  def error?
    !@error.nil?
  end

  def help_text?
    !@help_text.nil? && !error?
  end

  def prompt_selected?
    @selected.nil?
  end

  def option_selected?(value)
    value == @selected
  end

  def css_classes
    [
      BASE_CLASSES,
      SIZES[@size],
      (error? ? ERROR_CLASSES : nil)
    ].compact.join(" ")
  end

  def select_attrs
    attrs = @html_options.merge(
      name: @name,
      id: select_id,
      class: css_classes
    )
    attrs[:required] = true if @required
    if error?
      attrs[:"aria-invalid"] = "true"
      attrs[:"aria-describedby"] = error_id
    elsif help_text?
      attrs[:"aria-describedby"] = help_id
    end
    attrs
  end

  attr_reader :label, :required, :error, :help_text, :options, :prompt

  private

  def validate_options!(options)
    unless options.is_a?(Array)
      raise ArgumentError, "options must be an Array of [label, value] pairs"
    end

    options.each do |pair|
      unless pair.is_a?(Array) && pair.size == 2
        raise ArgumentError, "options must be an Array of [label, value] pairs"
      end
    end
  end
end
