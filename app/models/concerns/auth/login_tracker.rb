module Auth
  module LoginTracker
    extend ActiveSupport::Concern

    # Called from Auth::SessionCreator after resolving Case A/B/C.
    # Core tracking is atomic: identity.last_login_at + user.primary_identity_id
    # + user.last_seen_at. The email mirror is a separate, best-effort step so a
    # conflicting address can never roll back or 500 the sign-in.
    def track_login!(identity)
      transaction do
        identity.update!(last_login_at: Time.current)
        update!(primary_identity_id: identity.id, last_seen_at: Time.current)
      end
      mirror_email!(identity)
      self
    end

    private

    # Mirror user.email onto the now-primary identity's (verified) email so the
    # canonical email never goes stale. Skip when another user already holds the
    # address; rescue a lost concurrent uniqueness race the guard can't see.
    # Either way the sign-in succeeds with the stale email for an operator to fix.
    def mirror_email!(identity)
      return if email == identity.email
      return if User.where.not(id: id).exists?(email: identity.email)

      update!(email: identity.email)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      reload
    end
  end
end
