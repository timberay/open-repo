# frozen_string_literal: true

# DigestComponent renders a truncated digest with a click-to-copy button.
#
# Displays the first 12 hex characters of a `sha256:...` digest and exposes
# the full digest value to the Stimulus `clipboard` controller for copying.
#
# Usage:
#   <%= render DigestComponent.new(digest: layer.blob.digest) %>
class DigestComponent < ViewComponent::Base
  SHORT_LENGTH = 12

  def initialize(digest:)
    @digest = digest.to_s
  end

  def full
    @digest
  end

  def short
    @digest.sub(/\Asha256:/, "")[0, SHORT_LENGTH].to_s
  end
end
