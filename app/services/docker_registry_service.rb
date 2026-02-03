# frozen_string_literal: true

class DockerRegistryService
  class RegistryError < StandardError; end
  class AuthenticationError < RegistryError; end
  class NotFoundError < RegistryError; end

  CACHE_TTL = 5.minutes

  def initialize(url: nil, username: nil, password: nil)
    @url = url || Rails.application.config.registry_url
    @username = username || Rails.application.config.registry_username
    @password = password || Rails.application.config.registry_password
    @connection = build_connection
  end

  def catalog(query: nil, page: nil)
    cache_key = "registry:catalog:#{query}:#{page}"
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      params = {}
      params[:n] = 100
      params[:last] = page if page.present?

      response = @connection.get("/v2/_catalog", params)
      data = JSON.parse(response.body)

      repositories = data["repositories"] || []
      repositories = repositories.select { |repo| repo.include?(query) } if query.present?

      { repositories: repositories, next_page: parse_link_header(response.headers["link"]) }
    end
  rescue Faraday::ConnectionFailed => e
    raise RegistryError, "Connection failed: #{e.message}"
  rescue Faraday::TimeoutError
    raise RegistryError, "Connection timed out"
  rescue Faraday::UnauthorizedError
    raise AuthenticationError, "Authentication failed"
  rescue Faraday::Error => e
    raise RegistryError, "Registry error: #{e.message}"
  end

  def tags(repository_name)
    cache_key = "registry:tags:#{repository_name}"
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      response = @connection.get("/v2/#{repository_name}/tags/list")
      data = JSON.parse(response.body)

      data["tags"] || []
    end
  rescue Faraday::ConnectionFailed => e
    raise RegistryError, "Connection failed: #{e.message}"
  rescue Faraday::TimeoutError
    raise RegistryError, "Connection timed out"
  rescue Faraday::ResourceNotFound
    raise NotFoundError, "Repository not found: #{repository_name}"
  rescue Faraday::UnauthorizedError
    raise AuthenticationError, "Authentication failed"
  rescue Faraday::Error => e
    raise RegistryError, "Registry error: #{e.message}"
  end

  def manifest(repository_name, tag)
    response = @connection.get("/v2/#{repository_name}/manifests/#{tag}") do |req|
      req.headers["Accept"] = "application/vnd.docker.distribution.manifest.v2+json"
    end

    manifest_data = JSON.parse(response.body)
    digest = response.headers["docker-content-digest"]

    { manifest: manifest_data, digest: digest }
  rescue Faraday::ConnectionFailed => e
    raise RegistryError, "Connection failed: #{e.message}"
  rescue Faraday::TimeoutError
    raise RegistryError, "Connection timed out"
  rescue Faraday::ResourceNotFound
    raise NotFoundError, "Manifest not found: #{repository_name}:#{tag}"
  rescue Faraday::Error => e
    raise RegistryError, "Registry error: #{e.message}"
  end

  private

  def build_connection
    Faraday.new(url: @url) do |f|
      f.request :authorization, :basic, @username, @password if @username && @password
      f.request :retry, max: 3, interval: 0.5, backoff_factor: 2
      f.response :raise_error
      f.adapter Faraday.default_adapter
      f.options.timeout = 10
      f.options.open_timeout = 5
    end
  end

  def parse_link_header(link_header)
    return nil unless link_header

    # Parse: </v2/_catalog?last=repo-name&n=100>; rel="next"
    match = link_header.match(/<[^>]*[?&]last=([^&>]+)/)
    match[1] if match
  end
end
