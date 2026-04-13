require 'rails_helper'

RSpec.describe BlobStore do
  let(:storage_dir) { Dir.mktmpdir }
  let(:store) { BlobStore.new(storage_dir) }

  after { FileUtils.rm_rf(storage_dir) }

  describe '#put and #get' do
    it 'stores and retrieves a blob by digest' do
      content = 'hello blob'
      digest = DigestCalculator.compute(content)

      store.put(digest, StringIO.new(content))
      io = store.get(digest)
      expect(io.read).to eq(content)
    end

    it 'skips write if blob already exists' do
      content = 'hello blob'
      digest = DigestCalculator.compute(content)

      store.put(digest, StringIO.new(content))
      path = store.path_for(digest)
      mtime_before = File.mtime(path)

      sleep 0.01
      store.put(digest, StringIO.new(content))
      expect(File.mtime(path)).to eq(mtime_before)
    end
  end

  describe '#exists?' do
    it 'returns false for non-existent blob' do
      expect(store.exists?('sha256:nonexistent')).to be false
    end

    it 'returns true after storing' do
      content = 'test'
      digest = DigestCalculator.compute(content)
      store.put(digest, StringIO.new(content))
      expect(store.exists?(digest)).to be true
    end
  end

  describe '#delete' do
    it 'removes blob from disk' do
      content = 'test'
      digest = DigestCalculator.compute(content)
      store.put(digest, StringIO.new(content))
      store.delete(digest)
      expect(store.exists?(digest)).to be false
    end
  end

  describe '#path_for' do
    it 'uses sharded directory structure' do
      path = store.path_for('sha256:aabbccdd1234')
      expect(path).to include('/blobs/sha256/aa/aabbccdd1234')
    end
  end

  describe '#size' do
    it 'returns file size' do
      content = 'hello blob'
      digest = DigestCalculator.compute(content)
      store.put(digest, StringIO.new(content))
      expect(store.size(digest)).to eq(content.bytesize)
    end
  end

  describe 'upload lifecycle' do
    let(:uuid) { SecureRandom.uuid }

    it 'creates, appends, and finalizes an upload' do
      store.create_upload(uuid)
      expect(store.upload_size(uuid)).to eq(0)

      chunk1 = 'hello '
      chunk2 = 'world'
      store.append_upload(uuid, StringIO.new(chunk1))
      expect(store.upload_size(uuid)).to eq(6)

      store.append_upload(uuid, StringIO.new(chunk2))
      expect(store.upload_size(uuid)).to eq(11)

      content = chunk1 + chunk2
      digest = DigestCalculator.compute(content)
      store.finalize_upload(uuid, digest)

      expect(store.exists?(digest)).to be true
      expect(store.get(digest).read).to eq(content)
    end

    it 'raises DigestMismatch on finalize with wrong digest' do
      store.create_upload(uuid)
      store.append_upload(uuid, StringIO.new('hello'))

      expect {
        store.finalize_upload(uuid, 'sha256:wrong')
      }.to raise_error(Registry::DigestMismatch)
    end

    it 'cancels an upload and cleans up' do
      store.create_upload(uuid)
      store.append_upload(uuid, StringIO.new('data'))
      store.cancel_upload(uuid)

      expect { store.upload_size(uuid) }.to raise_error(Errno::ENOENT)
    end
  end

  describe '#cleanup_stale_uploads' do
    it 'removes uploads older than max_age' do
      uuid = SecureRandom.uuid
      store.create_upload(uuid)
      store.append_upload(uuid, StringIO.new('data'))

      # Backdate the startedat file
      startedat_path = File.join(storage_dir, 'uploads', uuid, 'startedat')
      File.write(startedat_path, 2.hours.ago.iso8601)

      store.cleanup_stale_uploads(max_age: 1.hour)
      expect(Dir.exist?(File.join(storage_dir, 'uploads', uuid))).to be false
    end
  end
end
