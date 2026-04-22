module RepositoriesHelper
  def docker_pull_command(repository_name, tag_name = "latest")
    host = Rails.configuration.registry_host
    "docker pull #{host}/#{repository_name}:#{tag_name}"
  end

  def human_size(bytes)
    return "0 B" if bytes.nil? || bytes == 0

    units = [ "B", "KB", "MB", "GB", "TB" ]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = units.length - 1 if exp >= units.length
    format("%.1f %s", bytes.to_f / 1024**exp, units[exp])
  end

  def short_digest(digest)
    return "" unless digest
    digest.sub("sha256:", "")[0..11]
  end
end
