# frozen_string_literal: true

class Tag
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :digest, :string
  attribute :size, :integer
  attribute :created_at, :datetime

  def self.from_manifest(tag_name, manifest_data, digest)
    # Calculate total size from manifest layers
    total_size = 0
    if manifest_data["layers"]
      total_size = manifest_data["layers"].sum { |layer| layer["size"] || 0 }
    end

    new(
      name: tag_name,
      digest: digest,
      size: total_size,
      created_at: Time.current # In real implementation, parse from config
    )
  end

  def pull_command(registry_host, repository_name)
    "docker pull #{registry_host}/#{repository_name}:#{name}"
  end

  def short_digest
    digest&.split(":")&.last&.first(12)
  end

  def human_size
    return "N/A" if size.nil? || size.zero?

    units = [ "B", "KB", "MB", "GB" ]
    size_float = size.to_f
    unit_index = 0

    while size_float >= 1024 && unit_index < units.length - 1
      size_float /= 1024
      unit_index += 1
    end

    "#{size_float.round(2)} #{units[unit_index]}"
  end
end
