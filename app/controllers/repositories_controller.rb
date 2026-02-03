class RepositoriesController < ApplicationController
  include RegistryErrorHandler

  before_action :initialize_registry_service

  def index
    @query = params[:query]
    @sort_by = params[:sort_by] || "name"
    @page = params[:page]

    result = @registry_service.catalog(query: @query, page: @page)
    @repositories = Repository.from_catalog(result[:repositories])
    @next_page = result[:next_page]

    @repositories = sort_repositories(@repositories, @sort_by)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    @repository_name = params[:id]
    @registry_host = extract_registry_host

    tag_names = @registry_service.tags(@repository_name)
    @tags = tag_names.map do |tag_name|
      manifest_data = @registry_service.manifest(@repository_name, tag_name)
      Tag.from_manifest(tag_name, manifest_data[:manifest], manifest_data[:digest])
    end

    @tags.sort_by!(&:created_at).reverse!
  end

  private

  def initialize_registry_service
    if Rails.application.config.use_mock_registry
      @registry_service = MockRegistryService.new
      return
    end

    registry = current_registry

    if registry
      @registry_service = DockerRegistryService.new(
        url: registry.url,
        username: registry.username,
        password: registry.password
      )
    else
      @registry_service = DockerRegistryService.new
    end
  end

  def sort_repositories(repositories, sort_by)
    case sort_by
    when "name_desc"
      repositories.sort_by(&:name).reverse
    when "name"
      repositories.sort_by(&:name)
    else
      repositories
    end
  end

  def extract_registry_host
    if Rails.application.config.use_mock_registry
      "registry.example.com"
    elsif current_registry
      uri = URI.parse(current_registry.url)
      port_suffix = uri.port && ![ 80, 443 ].include?(uri.port) ? ":#{uri.port}" : ""
      "#{uri.host}#{port_suffix}"
    else
      uri = URI.parse(Rails.application.config.registry_url)
      port_suffix = uri.port && ![ 80, 443 ].include?(uri.port) ? ":#{uri.port}" : ""
      "#{uri.host}#{port_suffix}"
    end
  end
end
