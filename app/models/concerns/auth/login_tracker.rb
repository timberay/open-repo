module Auth
  module LoginTracker
    extend ActiveSupport::Concern

    # Called from Auth::SessionCreator after resolving Case A/B/C.
    # Single transaction: identity.last_login_at + user.primary_identity_id + user.last_seen_at.
    def track_login!(identity)
      transaction do
        identity.update!(last_login_at: Time.current)
        update!(primary_identity_id: identity.id, last_seen_at: Time.current)
      end
      self
    end
  end
end
