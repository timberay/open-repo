# frozen_string_literal: true

# BadgeComponent renders status badges per DESIGN.md section 3.5.
#
# Six variants:
#   * default — slate (neutral)
#   * success — green
#   * warning — yellow
#   * danger  — red
#   * info    — blue (brand)
#   * accent  — amber
#
# Light mode uses *-200 backgrounds with *-800 text to satisfy the
# Light Mode Minimum Contrast Rule (resolves the DESIGN.md *-50 conflict).
#
# Usage:
#   <%= render BadgeComponent.new(variant: :info) { "Docker Image" } %>
#   <%= render BadgeComponent.new(variant: :warning, icon: "lock-closed") { "Protected" } %>
#   <%= render BadgeComponent.new { "default" } %>
class BadgeComponent < ViewComponent::Base
  # Tailwind class strings per DESIGN.md 3.5 with Light Mode Minimum Contrast.
  VARIANTS = {
    default: "bg-slate-200 text-slate-800 " \
             "dark:bg-slate-700 dark:text-slate-300",
    success: "bg-green-200 text-green-800 ring-1 ring-inset ring-green-600/20 " \
             "dark:bg-green-900/30 dark:text-green-400 dark:ring-green-400/20",
    warning: "bg-yellow-200 text-yellow-800 ring-1 ring-inset ring-yellow-600/20 " \
             "dark:bg-yellow-900/30 dark:text-yellow-400 dark:ring-yellow-400/20",
    danger: "bg-red-200 text-red-800 ring-1 ring-inset ring-red-600/20 " \
            "dark:bg-red-900/30 dark:text-red-400 dark:ring-red-400/20",
    info: "bg-blue-200 text-blue-800 ring-1 ring-inset ring-blue-600/20 " \
          "dark:bg-blue-900/30 dark:text-blue-400 dark:ring-blue-400/20",
    accent: "bg-amber-200 text-amber-800 ring-1 ring-inset ring-amber-600/20 " \
            "dark:bg-amber-900/30 dark:text-amber-400 dark:ring-amber-400/20"
  }.freeze

  BASE_CLASSES = "inline-flex items-center rounded-full px-2.5 py-1 " \
                 "text-sm font-medium"

  ICON_CLASSES = "w-3.5 h-3.5"

  def initialize(variant: :default, icon: nil, **html_options)
    raise ArgumentError, "unknown variant: #{variant.inspect}" unless VARIANTS.key?(variant)

    @variant = variant
    @icon = icon
    @html_options = html_options
  end

  def css_classes
    [
      BASE_CLASSES,
      VARIANTS[@variant],
      (@icon ? "gap-1.5" : nil)
    ].compact.join(" ")
  end

  def icon_classes
    ICON_CLASSES
  end

  def tag_options
    @html_options.merge(class: css_classes)
  end

  attr_reader :icon
end
