# CardComponentPreview exercises header/footer slot combinations and both
# padding modes. Visit `/rails/view_components` to browse.
class CardComponentPreview < ViewComponent::Preview
  # Default: body-only card.
  def default
    render CardComponent.new do
      "Body content. Lorem ipsum dolor sit amet, consectetur adipiscing elit."
    end
  end

  # Card with a simple string header.
  def with_header
    render CardComponent.new do |card|
      card.with_header { "Repository details" }
      "Pulled 42 times in the last 30 days."
    end
  end

  # Card with both header and footer slots.
  def with_header_and_footer
    render CardComponent.new do |card|
      card.with_header { "Danger zone" }
      card.with_footer { "Footer actions go here." }
      "Destructive actions live in this panel."
    end
  end

  # Card with a rich header (title + subtitle) matching DESIGN.md typography.
  def with_rich_header
    render CardComponent.new do |card|
      card.with_header do
        # rubocop:disable Rails/OutputSafety
        (
          '<h3 class="text-lg font-semibold text-slate-900 dark:text-slate-100">Layers (7)</h3>' \
          '<p class="text-sm text-slate-600 dark:text-slate-400 mt-1">' \
          "Filesystem layers composing this image." \
          "</p>"
        ).html_safe
        # rubocop:enable Rails/OutputSafety
      end
      "Body content below the rich header."
    end
  end

  # Card with `padding: :none` used to embed a divided list (e.g., table rows).
  def padding_none
    # rubocop:disable Rails/OutputSafety
    render(CardComponent.new(padding: :none)) do
      (
        '<ul class="divide-y divide-slate-200 dark:divide-slate-700">' \
        '<li class="px-6 py-3">Row one</li>' \
        '<li class="px-6 py-3">Row two</li>' \
        '<li class="px-6 py-3">Row three</li>' \
        "</ul>"
      ).html_safe
    end
    # rubocop:enable Rails/OutputSafety
  end

  # Card with `padding: :none` plus a header slot — typical for embedded tables
  # that want the header to carry its own spacing while rows sit flush.
  def padding_none_with_header
    # rubocop:disable Rails/OutputSafety
    render(CardComponent.new(padding: :none)) do |card|
      card.with_header { "Tag history" }
      (
        '<ul class="divide-y divide-slate-200 dark:divide-slate-700">' \
        '<li class="px-6 py-3">v1.2.0 — pushed 3 days ago</li>' \
        '<li class="px-6 py-3">v1.1.0 — pushed 2 weeks ago</li>' \
        '<li class="px-6 py-3">v1.0.0 — pushed 1 month ago</li>' \
        "</ul>"
      ).html_safe
    end
    # rubocop:enable Rails/OutputSafety
  end
end
