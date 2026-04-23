class AddOwnerIdentityToRepositories < ActiveRecord::Migration[8.1]
  def up
    add_reference :repositories, :owner_identity,
                  foreign_key: { to_table: :identities, on_delete: :restrict },
                  null: true
    # NOT NULL 전환은 PR-2 에서 first-pusher-owner 구현 이후 별도 마이그레이션으로 수행.

    # 기존 repo 가 있을 때만 REGISTRY_ADMIN_EMAIL 에 지정된 사용자로 backfill.
    # 빈 DB (test schema:load, CI fresh 등) 에서는 env 가 없어도 통과.
    if Repository.where(owner_identity_id: nil).exists?
      admin_email    = ENV.fetch("REGISTRY_ADMIN_EMAIL")
      admin_user     = User.find_by!(email: admin_email)
      Repository.where(owner_identity_id: nil)
                .update_all(owner_identity_id: admin_user.primary_identity_id)
    end
  end

  def down
    remove_reference :repositories, :owner_identity,
                     foreign_key: { to_table: :identities }
  end
end
