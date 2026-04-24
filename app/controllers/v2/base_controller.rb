class V2::BaseController < ActionController::API
  include RepositoryAuthorization

  before_action :set_registry_headers
  before_action :authenticate_v2_basic!, unless: :anonymous_pull_allowed?

  attr_reader :current_user, :current_pat

  rescue_from Registry::BlobUnknown, with: ->(e) { render_error("BLOB_UNKNOWN", e.message, 404) }
  rescue_from Registry::BlobUploadUnknown, with: ->(e) { render_error("BLOB_UPLOAD_UNKNOWN", e.message, 404) }
  rescue_from Registry::ManifestUnknown, with: ->(e) { render_error("MANIFEST_UNKNOWN", e.message, 404) }
  rescue_from Registry::ManifestInvalid, with: ->(e) { render_error("MANIFEST_INVALID", e.message, 400) }
  rescue_from Registry::NameUnknown, with: ->(e) { render_error("NAME_UNKNOWN", e.message, 404) }
  rescue_from Registry::DigestMismatch, with: ->(e) { render_error("DIGEST_INVALID", e.message, 400) }
  rescue_from Registry::Unsupported, with: ->(e) { render_error("UNSUPPORTED", e.message, 415) }
  rescue_from Registry::TagProtected, with: ->(e) { render_error("DENIED", e.message, 409, detail: e.detail) }
  rescue_from Auth::Unauthenticated, with: ->(_e) { render_v2_challenge }
  rescue_from Auth::ForbiddenAction, with: ->(e) {
    render_error(
      "DENIED",
      "insufficient_scope: #{e.action} privilege required on repository '#{e.repository.name}'",
      403,
      detail: { action: e.action.to_s, repository: e.repository.name }
    )
  }

  def index
    render json: {}
  end

  private

  ANONYMOUS_PULL_ENDPOINTS = [
    %w[base index],
    %w[catalog index],
    %w[tags index],
    %w[manifests show],
    %w[blobs show]
  ].freeze

  def anonymous_pull_allowed?
    return false unless Rails.configuration.x.registry.anonymous_pull_enabled
    return false unless request.get? || request.head?
    ANONYMOUS_PULL_ENDPOINTS.include?([ controller_name, action_name ])
  end

  def authenticate_v2_basic!
    email, raw = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
    raise Auth::Unauthenticated if email.blank? || raw.blank?

    result = Auth::PatAuthenticator.new.call(email: email, raw_token: raw)
    @current_user = result.user
    @current_pat  = result.pat
    result.pat.update_column(:last_used_at, Time.current)
  rescue Auth::Unauthenticated, Auth::PatInvalid
    render_v2_challenge
  end

  def render_v2_challenge
    response.headers["WWW-Authenticate"]                = %(Basic realm="Registry")
    response.headers["Docker-Distribution-API-Version"] = "registry/2.0"
    render json: {
      errors: [ { code: "UNAUTHORIZED", message: "authentication required", detail: nil } ]
    }, status: :unauthorized
  end

  def set_registry_headers
    response.headers["Docker-Distribution-API-Version"] = "registry/2.0"
  end

  def render_error(code, message, status, detail: {})
    render json: { errors: [ { code: code, message: message, detail: detail } ] }, status: status
  end

  def repo_name
    params[:ns].present? ? "#{params[:ns]}/#{params[:name]}" : params[:name]
  end

  def find_repository!
    Repository.find_by!(name: repo_name)
  rescue ActiveRecord::RecordNotFound
    raise Registry::NameUnknown, "repository '#{repo_name}' not found"
  end
end
