module Auth
  class SessionCreator
    def call(profile)
      raise Auth::InvalidProfile, "profile email blank" if profile.email.blank?

      # Verify before the domain check so unverified profiles always fail the
      # same way (EmailMismatch) regardless of domain — the failure can't be
      # used as an allowlist-membership oracle. Applies to Cases A/B/C alike.
      require_verified!(profile)
      ensure_allowed_domain!(profile)

      User.transaction do
        identity = Identity.find_by(provider: profile.provider, uid: profile.uid)
        user =
          if identity
            # Case A — existing (provider, uid)
            identity.update!(email: profile.email) if identity.email != profile.email
            identity.user
          elsif (matched = User.find_by(email: profile.email))
            # Case B — email matches existing user
            identity = matched.identities.create!(
              provider: profile.provider,
              uid: profile.uid,
              email: profile.email,
              email_verified: profile.email_verified,
              name: profile.name,
              avatar_url: profile.avatar_url
            )
            matched
          else
            # Case C — brand-new user
            new_user = User.create!(
              email: profile.email,
              admin: User.admin_email?(profile.email)
            )
            identity = new_user.identities.create!(
              provider: profile.provider,
              uid: profile.uid,
              email: profile.email,
              email_verified: profile.email_verified,
              name: profile.name,
              avatar_url: profile.avatar_url
            )
            new_user
          end

        user.track_login!(identity)
        user
      end
    end

    private

    # Opt-in sign-up restriction. When `allowed_email_domains` is configured,
    # only emails whose domain is in the list may sign in. Blank list (default)
    # allows any verified email, preserving the open sign-up behavior.
    #
    # Note: this gates sign-in only. Existing app sessions and previously issued
    # PATs are not re-checked here; revoke them separately when tightening policy.
    def ensure_allowed_domain!(profile)
      allowed = Rails.configuration.x.registry.allowed_email_domains
      return if allowed.blank?

      domain = Auth::AllowedEmailDomains.domain_for(profile.email)
      return if domain && allowed.include?(domain)

      # Message is intentionally free of attacker-controlled input (no domain
      # interpolation) so it is safe to log verbatim.
      raise Auth::UnauthorizedDomain, "email domain not allowed"
    end

    def require_verified!(profile)
      return if profile.email_verified == true

      raise Auth::EmailMismatch,
            "provider did not verify identity=#{profile.provider}:#{profile.uid}"
    end
  end
end
