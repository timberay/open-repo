class DigestCalculator
  CHUNK_SIZE = 64 * 1024 # 64KB

  def self.compute(io_or_string)
    sha = Digest::SHA256.new

    if io_or_string.is_a?(String)
      sha.update(io_or_string)
    else
      io_or_string.rewind if io_or_string.respond_to?(:rewind)
      while (chunk = io_or_string.read(CHUNK_SIZE))
        sha.update(chunk)
      end
      io_or_string.rewind if io_or_string.respond_to?(:rewind)
    end

    "sha256:#{sha.hexdigest}"
  end

  def self.verify!(io, expected_digest)
    actual = compute(io)
    return if actual == expected_digest

    raise Registry::DigestMismatch,
      "digest mismatch: expected #{expected_digest}, got #{actual}"
  end
end
