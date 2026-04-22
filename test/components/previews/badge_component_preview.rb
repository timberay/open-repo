# BadgeComponentPreview renders every variant x (with/without icon) combo.
# Visit `/rails/view_components` to browse.
class BadgeComponentPreview < ViewComponent::Preview
  # Default badge: default variant, no icon.
  def default
    render BadgeComponent.new { "Default" }
  end

  # ----- Without icon -----

  def default_without_icon
    render BadgeComponent.new(variant: :default) { "Default" }
  end

  def success_without_icon
    render BadgeComponent.new(variant: :success) { "Success" }
  end

  def warning_without_icon
    render BadgeComponent.new(variant: :warning) { "Warning" }
  end

  def danger_without_icon
    render BadgeComponent.new(variant: :danger) { "Danger" }
  end

  def info_without_icon
    render BadgeComponent.new(variant: :info) { "Info" }
  end

  def accent_without_icon
    render BadgeComponent.new(variant: :accent) { "Accent" }
  end

  # ----- With icon -----

  def default_with_icon
    render BadgeComponent.new(variant: :default, icon: "tag") { "Default" }
  end

  def success_with_icon
    render BadgeComponent.new(variant: :success, icon: "check") { "Success" }
  end

  def warning_with_icon
    render BadgeComponent.new(variant: :warning, icon: "exclamation-triangle") { "Warning" }
  end

  def danger_with_icon
    render BadgeComponent.new(variant: :danger, icon: "x-circle") { "Danger" }
  end

  def info_with_icon
    render BadgeComponent.new(variant: :info, icon: "information-circle") { "Info" }
  end

  def accent_with_icon
    render BadgeComponent.new(variant: :accent, icon: "sparkles") { "Accent" }
  end
end
