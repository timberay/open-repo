class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_registry

  private

  def current_registry
    return nil if Rails.application.config.use_mock_registry

    if session[:current_registry_id]
      Registry.find_by(id: session[:current_registry_id], is_active: true)
    else
      Registry.default || Registry.active.first
    end
  end
end
