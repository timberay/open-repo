# frozen_string_literal: true

class MockRegistryService
  MOCK_REPOSITORIES = [
    "app/backend",
    "app/frontend",
    "app/worker",
    "services/auth",
    "services/api",
    "services/db",
    "infra/nginx",
    "infra/redis",
    "ml/model-trainer",
    "ml/inference-service",
    "data/etl-pipeline",
    "data/analytics"
  ].freeze

  MOCK_TAGS = {
    "default" => [ "latest", "v1.0.0", "v1.1.0", "v2.0.0", "develop" ],
    "simple" => [ "latest", "stable" ],
    "versioned" => [ "v1.0.0", "v1.0.1", "v1.1.0", "v2.0.0", "v2.1.0" ]
  }.freeze

  def catalog(query: nil, page: nil)
    repositories = MOCK_REPOSITORIES.dup
    repositories = repositories.select { |repo| repo.include?(query) } if query.present?

    # Simulate pagination
    page_size = 100
    start_index = page.present? ? (repositories.index(page) || 0) + 1 : 0
    paginated_repos = repositories[start_index, page_size] || []
    next_page = paginated_repos.size == page_size ? paginated_repos.last : nil

    { repositories: paginated_repos, next_page: next_page }
  end

  def tags(repository_name)
    # Return different tag sets based on repository name
    if repository_name.include?("backend") || repository_name.include?("frontend")
      MOCK_TAGS["versioned"]
    elsif repository_name.include?("infra")
      MOCK_TAGS["simple"]
    else
      MOCK_TAGS["default"]
    end
  end

  def manifest(repository_name, tag)
    {
      manifest: {
        "schemaVersion" => 2,
        "mediaType" => "application/vnd.docker.distribution.manifest.v2+json",
        "config" => {
          "size" => rand(5000..10000),
          "digest" => "sha256:#{SecureRandom.hex(32)}"
        },
        "layers" => [
          {
            "size" => rand(50_000_000..200_000_000),
            "digest" => "sha256:#{SecureRandom.hex(32)}"
          },
          {
            "size" => rand(10_000_000..50_000_000),
            "digest" => "sha256:#{SecureRandom.hex(32)}"
          }
        ]
      },
      digest: "sha256:#{SecureRandom.hex(32)}"
    }
  end
end
