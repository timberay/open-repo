module Registry
  class Error < StandardError; end
  class BlobUnknown < Error; end
  class BlobUploadUnknown < Error; end
  class ManifestUnknown < Error; end
  class ManifestInvalid < Error; end
  class NameUnknown < Error; end
  class DigestMismatch < Error; end
  class DigestInvalid < Error; end
  class Unsupported < Error; end

  class TagProtected < Error
    attr_reader :detail

    def initialize(tag:, policy:, message: nil)
      @detail = { tag: tag, policy: policy }
      super(message || "tag '#{tag}' is protected by immutability policy '#{policy}'")
    end
  end
end
