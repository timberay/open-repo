# InputComponentPreview renders every type x size combo plus label,
# required, error, and help_text variations. Visit `/rails/view_components`.
class InputComponentPreview < ViewComponent::Preview
  # Default: text input with a label.
  def default
    render InputComponent.new(name: "title", label: "Title", placeholder: "Enter a title")
  end

  # ----- Types (md size) -----

  def text_type
    render InputComponent.new(name: "title", label: "Title", type: :text)
  end

  def email_type
    render InputComponent.new(name: "email", label: "Email", type: :email,
                              placeholder: "you@example.com")
  end

  def password_type
    render InputComponent.new(name: "password", label: "Password", type: :password)
  end

  def search_type
    render InputComponent.new(name: "q", type: :search, placeholder: "Search…")
  end

  # ----- Sizes (text type, with label) -----

  def size_sm
    render InputComponent.new(name: "title_sm", label: "Small", size: :sm)
  end

  def size_md
    render InputComponent.new(name: "title_md", label: "Medium", size: :md)
  end

  def size_lg
    render InputComponent.new(name: "title_lg", label: "Large", size: :lg)
  end

  # ----- States -----

  def required
    render InputComponent.new(name: "email", label: "Email", type: :email, required: true)
  end

  def with_value
    render InputComponent.new(name: "title", label: "Title", value: "Hello world")
  end

  def with_error
    render InputComponent.new(name: "title", label: "Title",
                              value: "", error: "Title can't be blank")
  end

  def with_help_text
    render InputComponent.new(name: "bio", label: "Bio",
                              help_text: "1-2 sentences about yourself")
  end

  def with_error_and_help_text
    render InputComponent.new(name: "bio", label: "Bio",
                              help_text: "1-2 sentences about yourself",
                              error: "Bio is too short")
  end

  def without_label
    render InputComponent.new(name: "q", type: :search, placeholder: "Search…")
  end
end
