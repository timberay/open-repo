# frozen_string_literal: true

# InputComponent renders brand-consistent form inputs per DESIGN.md section 3.3.
#
# Supports four input types: text, email, password, search.
# Three sizes (sm/md/lg map to h-8/h-10/h-12).
# Optional label with required-asterisk, error state with aria-describedby,
# and help text. Error takes precedence over help text when both are set.
#
# Usage:
#   <%= render InputComponent.new(name: "email", label: "Email", type: :email) %>
#   <%= render InputComponent.new(name: "search", size: :sm, type: :search,
#                                 placeholder: "Search…") %>
#   <%= render InputComponent.new(name: "password", type: :password,
#                                 label: "Password", required: true) %>
#   <%= render InputComponent.new(name: "title", label: "Title",
#                                 error: "Title can't be blank") %>
#   <%= render InputComponent.new(name: "bio", label: "Bio",
#                                 help_text: "1-2 sentences about yourself") %>
class InputComponent < ViewComponent::Base
  VALID_TYPES = %i[text email password search].freeze

  SIZES = {
    sm: "h-8",
    md: "h-10",
    lg: "h-12"
  }.freeze

  BASE_CLASSES = "w-full rounded-md border border-slate-200 dark:border-slate-600 " \
                 "bg-white dark:bg-slate-700 px-3 py-2 text-sm " \
                 "text-slate-900 dark:text-slate-100 " \
                 "placeholder:text-slate-400 dark:placeholder:text-slate-500 " \
                 "focus:outline-none focus:ring-2 focus:ring-blue-500/20 dark:focus:ring-blue-400/20 " \
                 "focus:border-blue-500 dark:focus:border-blue-400 " \
                 "transition-colors duration-150"

  ERROR_CLASSES = "border-red-500 focus:ring-red-500/20 focus:border-red-500"

  LABEL_CLASSES = "block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1.5"

  REQUIRED_MARK_CLASSES = "text-red-500 ml-0.5"

  ERROR_MESSAGE_CLASSES = "text-sm text-red-600 dark:text-red-400 mt-1.5"

  HELP_TEXT_CLASSES = "text-sm text-slate-500 dark:text-slate-400 mt-1.5"

  def initialize(name:, value: nil, type: :text, size: :md, label: nil,
                 placeholder: nil, required: false, error: nil, help_text: nil,
                 id: nil, **html_options)
    raise ArgumentError, "unknown type: #{type.inspect}" unless VALID_TYPES.include?(type)
    raise ArgumentError, "unknown size: #{size.inspect}" unless SIZES.key?(size)

    @name = name
    @value = value
    @type = type
    @size = size
    @label = label
    @placeholder = placeholder
    @required = required
    @error = error
    @help_text = help_text
    @id = id
    @html_options = html_options
  end

  def input_id
    @id || "input_#{@name}"
  end

  def error_id
    "#{input_id}_error"
  end

  def help_id
    "#{input_id}_help"
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
      SIZES[@size],
      (error? ? ERROR_CLASSES : nil)
    ].compact.join(" ")
  end

  def input_attrs
    attrs = @html_options.merge(
      type: @type,
      name: @name,
      id: input_id,
      class: css_classes
    )
    attrs[:value] = @value unless @value.nil?
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

  attr_reader :label, :required, :error, :help_text
end
