require 'rails_helper'

RSpec.describe DigestCalculator do
  describe '.compute' do
    it 'computes sha256 digest of a string' do
      digest = DigestCalculator.compute('hello world')
      expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest('hello world')}")
    end

    it 'computes sha256 digest of an IO stream' do
      io = StringIO.new('hello world')
      digest = DigestCalculator.compute(io)
      expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest('hello world')}")
    end

    it 'computes sha256 digest of a file' do
      Tempfile.create('test') do |f|
        f.write('hello world')
        f.rewind
        digest = DigestCalculator.compute(f)
        expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest('hello world')}")
      end
    end

    it 'handles large data in chunks' do
      large_data = SecureRandom.random_bytes(1024 * 1024)
      io = StringIO.new(large_data)
      digest = DigestCalculator.compute(io)
      expect(digest).to eq("sha256:#{Digest::SHA256.hexdigest(large_data)}")
    end
  end

  describe '.verify!' do
    it 'passes when digest matches' do
      data = 'hello world'
      expected = "sha256:#{Digest::SHA256.hexdigest(data)}"
      expect { DigestCalculator.verify!(StringIO.new(data), expected) }.not_to raise_error
    end

    it 'raises DigestMismatch when digest does not match' do
      expect {
        DigestCalculator.verify!(StringIO.new('hello'), 'sha256:wrong')
      }.to raise_error(Registry::DigestMismatch, /digest mismatch/)
    end
  end
end
