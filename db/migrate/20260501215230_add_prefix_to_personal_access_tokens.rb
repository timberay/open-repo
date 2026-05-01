class AddPrefixToPersonalAccessTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :personal_access_tokens, :prefix, :string
    # Backfill: existing rows lose distinguishing chars (raw token is gone),
    # but we can still assign the static "oprk_legacy" sentinel so the column
    # stays NOT NULL and readers don't have to handle nil. Display logic shows
    # the full prefix (12 chars) for new tokens.
    PersonalAccessToken.reset_column_information
    PersonalAccessToken.where(prefix: nil).update_all(prefix: "oprk_legacy")
    change_column_null :personal_access_tokens, :prefix, false
  end

  def down
    remove_column :personal_access_tokens, :prefix
  end
end
