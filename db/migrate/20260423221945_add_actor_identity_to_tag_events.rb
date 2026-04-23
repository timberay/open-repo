class AddActorIdentityToTagEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :tag_events, :actor_identity,
                  foreign_key: { to_table: :identities, on_delete: :nullify },
                  null: true
    # Legacy 행은 actor_identity_id = NULL.
    # TagEvent#display_actor 가 actor 문자열로 fallback 렌더 (Task 1.5 에서 구현).
  end
end
