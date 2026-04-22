# frozen_string_literal: true

# CardComponent renders a rounded white panel per DESIGN.md section 3.2.
#
# Supports two optional slots and a body (required `content`):
#   * `header` — rendered above the body, separated by a bottom border.
#   * `footer` — rendered below the body, separated by a top border, tinted bg.
#
# `padding:` controls body padding:
#   * `:default` (default) — body has `px-6 py-4`.
#   * `:none`              — body carries no padding; caller controls it
#                            (used when embedding tables, divided lists, etc.).
#
# Usage:
#   <%= render CardComponent.new do %>Body<% end %>
#
#   <%= render CardComponent.new do |card|
#         card.with_header { "Title" }
#         "Body"
#       end %>
#
#   <%= render CardComponent.new(padding: :none) do
#         render SomeTable.new
#       end %>
class CardComponent < ViewComponent::Base
  renders_one :header
  renders_one :footer

  WRAPPER_CLASSES = "rounded-lg bg-white dark:bg-slate-800 " \
                    "border border-slate-200 dark:border-slate-700 shadow-sm"

  HEADER_CLASSES = "px-6 py-4 border-b border-slate-200 dark:border-slate-700"

  FOOTER_CLASSES = "px-6 py-4 border-t border-slate-100 dark:border-slate-700 " \
                   "bg-slate-50/50 dark:bg-slate-800/50"

  BODY_PADDING = {
    default: "px-6 py-4",
    none: ""
  }.freeze

  def initialize(padding: :default, **html_options)
    raise ArgumentError, "unknown padding: #{padding.inspect}" unless BODY_PADDING.key?(padding)

    @padding = padding
    @html_options = html_options
  end

  def wrapper_classes
    [ WRAPPER_CLASSES, @html_options[:class] ].compact.join(" ").strip
  end

  def wrapper_options
    @html_options.except(:class).merge(class: wrapper_classes)
  end

  def header_classes
    HEADER_CLASSES
  end

  def footer_classes
    FOOTER_CLASSES
  end

  def body_classes
    BODY_PADDING[@padding]
  end
end
