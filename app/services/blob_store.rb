class BlobStore
  CHUNK_SIZE = 64 * 1024 # 64KB

  def initialize(root_path = Rails.configuration.storage_path)
    @root_path = root_path.to_s
  end

  # --- Blob management ---

  def get(digest)
    path = path_for(digest)
    File.open(path, 'rb')
  end

  def put(digest, io)
    target = path_for(digest)
    return if File.exist?(target)

    FileUtils.mkdir_p(File.dirname(target))
    tmp = "#{target}.#{SecureRandom.hex(8)}.tmp"

    File.open(tmp, 'wb') do |f|
      io.rewind if io.respond_to?(:rewind)
      while (chunk = io.read(CHUNK_SIZE))
        f.write(chunk)
      end
    end

    File.rename(tmp, target)
  rescue => e
    FileUtils.rm_f(tmp) if tmp
    raise e
  end

  def exists?(digest)
    File.exist?(path_for(digest))
  end

  def delete(digest)
    FileUtils.rm_f(path_for(digest))
  end

  def path_for(digest)
    algorithm, hex = digest.split(':')
    shard = hex[0..1]
    File.join(@root_path, 'blobs', algorithm, shard, hex)
  end

  def size(digest)
    File.size(path_for(digest))
  end

  # --- Upload session management ---

  def create_upload(uuid)
    dir = upload_dir(uuid)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'startedat'), Time.current.iso8601)
  end

  def append_upload(uuid, io)
    data_path = File.join(upload_dir(uuid), 'data')
    File.open(data_path, 'ab') do |f|
      io.rewind if io.respond_to?(:rewind)
      while (chunk = io.read(CHUNK_SIZE))
        f.write(chunk)
      end
    end
  end

  def upload_size(uuid)
    dir = upload_dir(uuid)
    raise Errno::ENOENT, "upload #{uuid} not found" unless Dir.exist?(dir)

    data_path = File.join(dir, 'data')
    File.exist?(data_path) ? File.size(data_path) : 0
  end

  def finalize_upload(uuid, digest)
    data_path = File.join(upload_dir(uuid), 'data')
    DigestCalculator.verify!(File.open(data_path, 'rb'), digest)
    put(digest, File.open(data_path, 'rb'))
    cancel_upload(uuid)
  end

  def cancel_upload(uuid)
    FileUtils.rm_rf(upload_dir(uuid))
  end

  def cleanup_stale_uploads(max_age: 1.hour)
    uploads_root = File.join(@root_path, 'uploads')
    return unless Dir.exist?(uploads_root)

    Dir.each_child(uploads_root) do |uuid|
      dir = File.join(uploads_root, uuid)
      startedat_path = File.join(dir, 'startedat')
      next unless File.exist?(startedat_path)

      started_at = Time.parse(File.read(startedat_path))
      FileUtils.rm_rf(dir) if started_at < max_age.ago
    end
  end

  private

  def upload_dir(uuid)
    File.join(@root_path, 'uploads', uuid)
  end
end
