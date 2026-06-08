module Auth
  module LoginTracker
    extend ActiveSupport::Concern

    # Called from Auth::SessionCreator after resolving Case A/B/C.
    # Single transaction: identity.last_login_at + user.primary_identity_id +
    # user.last_seen_at, and mirror user.email onto the now-primary identity's
    # (verified) email so the canonical email never goes stale.
    def track_login!(identity)
      transaction do
        identity.update!(last_login_at: Time.current)
        attrs = { primary_identity_id: identity.id, last_seen_at: Time.current }
        attrs[:email] = identity.email if sync_email_to?(identity)
        update!(**attrs)
      end
      self
    end

    private

    # Sync user.email onto the identity's email, but skip when another user
    # already holds that address — a real account conflict that must not break
    # this user's sign-in. The stale email is left for an operator to resolve.
    def sync_email_to?(identity)
      return false if email == identity.email

      !User.where.not(id: id).exists?(email: identity.email)
    end
  end
end
