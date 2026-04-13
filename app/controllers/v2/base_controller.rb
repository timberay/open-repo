class V2::BaseController < ActionController::API
  before_action :set_registry_headers

  rescue_from Registry::BlobUnknown, with: -> (e) { render_error('BLOB_UNKNOWN', e.message, 404) }
  rescue_from Registry::BlobUploadUnknown, with: -> (e) { render_error('BLOB_UPLOAD_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestUnknown, with: -> (e) { render_error('MANIFEST_UNKNOWN', e.message, 404) }
  rescue_from Registry::ManifestInvalid, with: -> (e) { render_error('MANIFEST_INVALID', e.message, 400) }
  rescue_from Registry::NameUnknown, with: -> (e) { render_error('NAME_UNKNOWN', e.message, 404) }
  rescue_from Registry::DigestMismatch, with: -> (e) { render_error('DIGEST_INVALID', e.message, 400) }
  rescue_from Registry::Unsupported, with: -> (e) { render_error('UNSUPPORTED', e.message, 415) }

  def index
    render json: {}
  end

  private

  def set_registry_headers
    response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'
  end

  def render_error(code, message, status, detail: {})
    render json: { errors: [{ code: code, message: message, detail: detail }] }, status: status
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
