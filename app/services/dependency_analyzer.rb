class DependencyAnalyzer
  def call(repository)
    layer_digests = repository.manifests
      .joins(layers: :blob)
      .pluck("blobs.digest")
      .uniq

    return [] if layer_digests.empty?

    other_repos = Repository
      .where.not(id: repository.id)
      .joins(manifests: { layers: :blob })
      .where(blobs: { digest: layer_digests })
      .group("repositories.id")
      .select("repositories.*, COUNT(DISTINCT blobs.digest) as shared_count")

    other_repos.map do |repo|
      total_layers = repo.manifests.joins(:layers).distinct.count("layers.blob_id")
      {
        repository: repo.name,
        shared_layers: repo.shared_count.to_i,
        total_layers: total_layers,
        ratio: total_layers > 0 ? repo.shared_count.to_f / total_layers : 0
      }
    end
  end
end
