module Auth
  module SafeReturn
    extend ActiveSupport::Concern

    private

    # Returns +path+ unchanged when it is a same-origin relative URL that
    # resolves to a real route in this application; otherwise returns nil.
    # Defends against open redirects (protocol-relative, absolute, unknown
    # routes, malformed URIs).
    def safe_return_to(path)
      return nil unless path.is_a?(String)
      return nil unless path.start_with?("/") && !path.start_with?("//")
      uri = URI.parse(path)
      Rails.application.routes.recognize_path(uri.path)
      path
    rescue URI::InvalidURIError, ActionController::RoutingError
      nil
    end
  end
end
