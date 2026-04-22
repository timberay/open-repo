# frozen_string_literal: true

# ButtonComponent renders brand-consistent buttons per DESIGN.md section 3.1.
#
# Three render modes selected from the initializer:
#   * default — `<button type="button">` (or custom `type:` like :submit)
#   * submit  — `<button type="submit">` (pass `type: :submit`)
#   * link    — `<a href="…">` (pass `href:`)
#
# Passing both `href:` and `type:` raises ArgumentError since `<a>` has no type.
#
# Usage:
#   <%= render ButtonComponent.new(variant: :primary) { "Save" } %>
#   <%= render ButtonComponent.new(variant: :primary, icon: "check") { "Save" } %>
#   <%= render ButtonComponent.new(variant: :outline, href: "/path") { "Go" } %>
#   <%= render ButtonComponent.new(variant: :ghost, icon: "x-mark",
#                                  "aria-label": "Close") %>
class ButtonComponent < ViewComponent::Base
  # Tailwind class strings copy DESIGN.md 3.1 verbatim. Brand color is `blue`.
  VARIANTS = {
    primary: "bg-blue-600 hover:bg-blue-700 text-white " \
             "dark:bg-blue-500 dark:hover:bg-blue-400",
    secondary: "bg-slate-100 hover:bg-slate-200 text-slate-700 " \
               "dark:bg-slate-700 dark:hover:bg-slate-600 dark:text-slate-200",
    outline: "border border-slate-200 hover:bg-slate-50 text-slate-700 " \
             "dark:border-slate-600 dark:hover:bg-slate-700 dark:text-slate-200",
    danger: "bg-red-600 hover:bg-red-700 text-white " \
            "dark:bg-red-500 dark:hover:bg-red-400",
    ghost: "hover:bg-slate-100 text-slate-600 " \
           "dark:hover:bg-slate-700 dark:text-slate-300",
    link: "text-blue-600 hover:text-blue-700 underline-offset-4 hover:underline " \
          "dark:text-blue-400 dark:hover:text-blue-300"
  }.freeze

  SIZES = {
    sm: "h-8 px-3 text-sm",
    md: "h-10 px-4 text-base",
    lg: "h-12 px-6 text-base"
  }.freeze

  ICON_SIZES = {
    sm: "w-4 h-4",
    md: "w-5 h-5",
    lg: "w-5 h-5"
  }.freeze

  BASE_CLASSES = "inline-flex items-center justify-center " \
                 "font-medium rounded-md transition-colors duration-150 " \
                 "focus-visible:ring-2 focus-visible:ring-blue-500/50 focus-visible:ring-offset-2 " \
                 "dark:focus-visible:ring-blue-400/50 dark:focus-visible:ring-offset-slate-900"

  DISABLED_CLASSES = "opacity-50 cursor-not-allowed pointer-events-none"

  def initialize(variant: :primary, size: :md, type: nil, href: nil,
                 disabled: false, icon: nil, **html_options)
    raise ArgumentError, "unknown variant: #{variant.inspect}" unless VARIANTS.key?(variant)
    raise ArgumentError, "unknown size: #{size.inspect}" unless SIZES.key?(size)
    raise ArgumentError, "cannot pass both href: and type:" if href && type

    @variant = variant
    @size = size
    @type = type || :button
    @href = href
    @disabled = disabled
    @icon = icon
    @html_options = html_options
  end

  def css_classes
    [
      BASE_CLASSES,
      VARIANTS[@variant],
      SIZES[@size],
      (@disabled ? DISABLED_CLASSES : nil),
      (@icon ? "gap-2" : nil)
    ].compact.join(" ")
  end

  def icon_classes
    ICON_SIZES[@size]
  end

  def link?
    !@href.nil?
  end

  def tag_options
    base = @html_options.merge(class: css_classes)
    if link?
      base[:href] = @href
      base[:"aria-disabled"] = "true" if @disabled
    else
      base[:type] = @type
      base[:disabled] = true if @disabled
    end
    base
  end

  attr_reader :icon
end
