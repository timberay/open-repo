class V2::TagsController < V2::BaseController
  def index
    repository = find_repository!
    n = (params[:n] || 100).to_i.clamp(1, 1000)
    scope = repository.tags.order(:name)
    scope = scope.where("name > ?", params[:last]) if params[:last].present?
    tags = scope.limit(n + 1).pluck(:name)

    if tags.size > n
      tags.pop
      response.headers["Link"] = "</v2/#{path_encode(repository.name)}/tags/list?n=#{n}&last=#{url_encode(tags.last)}>; rel=\"next\""
    end

    render json: { name: repository.name, tags: tags }
  end

  private

  def path_encode(value)
    value.split("/").map { |segment| url_encode(segment) }.join("/")
  end

  def url_encode(value)
    ERB::Util.url_encode(value)
  end
end
