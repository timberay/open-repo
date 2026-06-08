class ScopeManifestDigestUniquenessPerRepository < ActiveRecord::Migration[8.1]
  # Manifest digests are content-addressed, so identical image content yields
  # an identical digest in every repository. Enforcing global digest uniqueness
  # blocked pushing the same image to a second repository. Scope uniqueness to
  # (repository_id, digest) instead; Blob.digest stays globally unique (correct
  # for content-addressed storage shared across repositories).
  def up
    remove_index :manifests, name: "index_manifests_on_digest"
    remove_index :manifests, name: "index_manifests_on_repository_id_and_digest"
    add_index :manifests, [ :repository_id, :digest ], unique: true,
              name: "index_manifests_on_repository_id_and_digest"
  end

  def down
    remove_index :manifests, name: "index_manifests_on_repository_id_and_digest"
    add_index :manifests, [ :repository_id, :digest ],
              name: "index_manifests_on_repository_id_and_digest"
    add_index :manifests, :digest, unique: true, name: "index_manifests_on_digest"
  end
end
