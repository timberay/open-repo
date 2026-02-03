module RegistryErrorHandler
  extend ActiveSupport::Concern

  included do
    rescue_from DockerRegistryService::AuthenticationError, with: :handle_auth_error
    rescue_from DockerRegistryService::NotFoundError, with: :handle_not_found
    rescue_from DockerRegistryService::RegistryError, with: :handle_registry_error
  end

  private

  def handle_auth_error(exception)
    respond_to do |format|
      format.html { redirect_to registries_path, alert: "Authentication failed: #{exception.message}" }
      format.json { render json: { error: "Authentication failed: #{exception.message}" }, status: :unauthorized }
    end
  end

  def handle_not_found(exception)
    respond_to do |format|
      format.html { redirect_to root_path, alert: exception.message }
      format.json { render json: { error: exception.message }, status: :not_found }
    end
  end

  def handle_registry_error(exception)
    respond_to do |format|
      format.html { redirect_to registries_path, alert: "Registry Error: #{exception.message}" }
      format.json { render json: { error: exception.message }, status: :bad_gateway }
    end
  end
end
