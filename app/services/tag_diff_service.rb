class TagDiffService
  def call(manifest_a, manifest_b)
    layers_a = manifest_a.layers.includes(:blob).map { |l| l.blob.digest }
    layers_b = manifest_b.layers.includes(:blob).map { |l| l.blob.digest }

    common = layers_a & layers_b
    removed = layers_a - layers_b
    added = layers_b - layers_a

    size_a = Blob.where(digest: layers_a).sum(:size)
    size_b = Blob.where(digest: layers_b).sum(:size)

    config_a = parse_config(manifest_a.docker_config)
    config_b = parse_config(manifest_b.docker_config)

    {
      common_layers: common,
      removed_layers: removed,
      added_layers: added,
      size_delta: size_b - size_a,
      config_diff: diff_configs(config_a, config_b)
    }
  end

  private

  def parse_config(json_string)
    json_string.present? ? JSON.parse(json_string) : {}
  rescue JSON::ParserError
    {}
  end

  def diff_configs(a, b)
    all_keys = (a.keys + b.keys).uniq
    diff = {}
    all_keys.each do |key|
      next if a[key] == b[key]
      diff[key] = { before: a[key], after: b[key] }
    end
    diff
  end
end
