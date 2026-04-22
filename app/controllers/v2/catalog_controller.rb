class V2::CatalogController < V2::BaseController
  def index
    n = (params[:n] || 100).to_i.clamp(1, 1000)
    scope = Repository.order(:name)
    scope = scope.where("name > ?", params[:last]) if params[:last].present?
    repos = scope.limit(n + 1).pluck(:name)

    if repos.size > n
      repos.pop
      response.headers["Link"] = "</v2/_catalog?n=#{n}&last=#{repos.last}>; rel=\"next\""
    end

    render json: { repositories: repos }
  end
end
