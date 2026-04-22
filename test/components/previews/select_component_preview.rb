# SelectComponentPreview renders every size plus selected, prompt, label,
# required, error, and help_text variations. Visit `/rails/view_components`.
class SelectComponentPreview < ViewComponent::Preview
  ROLES = [ [ "User", "user" ], [ "Admin", "admin" ], [ "Guest", "guest" ] ].freeze

  # Default: select with a label.
  def default
    render SelectComponent.new(name: "role", label: "Role", options: ROLES)
  end

  # ----- Sizes (with label) -----

  def size_sm
    render SelectComponent.new(name: "role_sm", label: "Small", options: ROLES, size: :sm)
  end

  def size_md
    render SelectComponent.new(name: "role_md", label: "Medium", options: ROLES, size: :md)
  end

  def size_lg
    render SelectComponent.new(name: "role_lg", label: "Large", options: ROLES, size: :lg)
  end

  # ----- States -----

  def with_selected
    render SelectComponent.new(name: "role", label: "Role", options: ROLES, selected: "admin")
  end

  def with_prompt
    render SelectComponent.new(name: "role", label: "Role", options: ROLES,
                               prompt: "— select a role —")
  end

  def with_prompt_and_selected
    render SelectComponent.new(name: "role", label: "Role", options: ROLES,
                               prompt: "— select a role —", selected: "guest")
  end

  def required
    render SelectComponent.new(name: "role", label: "Role", options: ROLES, required: true)
  end

  def with_error
    render SelectComponent.new(name: "role", label: "Role", options: ROLES,
                               error: "Please choose a role")
  end

  def with_help_text
    render SelectComponent.new(name: "role", label: "Role", options: ROLES,
                               help_text: "Assign a role to this user")
  end

  def with_error_and_help_text
    render SelectComponent.new(name: "role", label: "Role", options: ROLES,
                               help_text: "Assign a role to this user",
                               error: "Please choose a role")
  end

  def without_label
    render SelectComponent.new(name: "role", options: ROLES, prompt: "— select —")
  end
end
