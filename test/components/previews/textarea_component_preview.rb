# TextareaComponentPreview renders the multi-line textarea in its core
# configurations: defaults, rows variations, label, required, value,
# error, help text, and a label-less variant. Visit `/rails/view_components`.
class TextareaComponentPreview < ViewComponent::Preview
  # Default: textarea with a label and 4 rows.
  def default
    render TextareaComponent.new(name: "bio", label: "Bio", placeholder: "Tell us about yourself…")
  end

  # ----- Rows -----

  def rows_4
    render TextareaComponent.new(name: "bio_4", label: "Rows: 4", rows: 4)
  end

  def rows_6
    render TextareaComponent.new(name: "notes", label: "Rows: 6",
                                 rows: 6, placeholder: "Your notes…")
  end

  def rows_10
    render TextareaComponent.new(name: "long", label: "Rows: 10", rows: 10)
  end

  # ----- States -----

  def required
    render TextareaComponent.new(name: "bio", label: "Bio", required: true)
  end

  def with_value
    render TextareaComponent.new(name: "description", label: "Description",
                                 value: "Hello, this is a pre-filled textarea.")
  end

  def with_error
    render TextareaComponent.new(name: "bio", label: "Bio",
                                 value: "", error: "Bio can't be blank")
  end

  def with_help_text
    render TextareaComponent.new(name: "bio", label: "Bio",
                                 help_text: "Short biography, 1-2 paragraphs")
  end

  def with_error_and_help_text
    render TextareaComponent.new(name: "bio", label: "Bio",
                                 help_text: "Short biography, 1-2 paragraphs",
                                 error: "Bio is too short")
  end

  def without_label
    render TextareaComponent.new(name: "notes", placeholder: "Your notes…", rows: 6)
  end
end
