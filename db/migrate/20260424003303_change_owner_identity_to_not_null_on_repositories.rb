class ChangeOwnerIdentityToNotNullOnRepositories < ActiveRecord::Migration[8.1]
  def up
    # Legacy safety: on the off chance any repo still has nil owner (fresh
    # environments that predate PR-2), backfill them with the admin identity
    # before tightening the constraint. No-op on populated production DBs.
    if Repository.where(owner_identity_id: nil).exists?
      admin_email       = ENV.fetch("REGISTRY_ADMIN_EMAIL")
      admin_identity_id = User.find_by!(email: admin_email).primary_identity_id
      Repository.where(owner_identity_id: nil)
                .update_all(owner_identity_id: admin_identity_id)
    end

    change_column_null :repositories, :owner_identity_id, false
  end

  def down
    change_column_null :repositories, :owner_identity_id, true
  end
end
