# ButtonComponentPreview renders every variant x size combo plus disabled,
# icon, submit, and link modes. Visit `/rails/view_components` to browse.
class ButtonComponentPreview < ViewComponent::Preview
  # Default button: primary variant, md size, icon+text.
  def default
    render ButtonComponent.new(variant: :primary, icon: "check") { "Save changes" }
  end

  # ----- Variants (md size, icon+text) -----

  def primary
    render ButtonComponent.new(variant: :primary, icon: "check") { "Save" }
  end

  def secondary
    render ButtonComponent.new(variant: :secondary, icon: "arrow-path") { "Refresh" }
  end

  def outline
    render ButtonComponent.new(variant: :outline, icon: "eye") { "Preview" }
  end

  def danger
    render ButtonComponent.new(variant: :danger, icon: "trash") { "Delete" }
  end

  def ghost
    render ButtonComponent.new(variant: :ghost, icon: "x-mark") { "Dismiss" }
  end

  def link
    render ButtonComponent.new(variant: :link, icon: "arrow-top-right-on-square") { "Open docs" }
  end

  # ----- Sizes (primary variant) -----

  def primary_sm
    render ButtonComponent.new(variant: :primary, size: :sm, icon: "check") { "Save" }
  end

  def primary_md
    render ButtonComponent.new(variant: :primary, size: :md, icon: "check") { "Save" }
  end

  def primary_lg
    render ButtonComponent.new(variant: :primary, size: :lg, icon: "check") { "Save" }
  end

  # ----- States -----

  def disabled
    render ButtonComponent.new(variant: :primary, icon: "check", disabled: true) { "Disabled" }
  end

  def without_icon
    render ButtonComponent.new(variant: :primary) { "Plain text button" }
  end

  # ----- Render modes -----

  def submit
    render ButtonComponent.new(variant: :primary, type: :submit, icon: "paper-airplane") { "Submit" }
  end

  def as_link
    render ButtonComponent.new(variant: :outline, href: "/", icon: "arrow-left") { "Back home" }
  end

  # ----- Icon-only -----

  def icon_only
    render ButtonComponent.new(variant: :ghost, icon: "x-mark",
                               "aria-label": "Close", class: "p-2 rounded-md")
  end
end
