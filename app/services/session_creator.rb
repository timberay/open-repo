class SessionCreator
  def call(profile)
    raise Auth::InvalidProfile, "profile email blank" if profile.email.blank?

    User.transaction do
      identity = Identity.find_by(provider: profile.provider, uid: profile.uid)
      user =
        if identity
          # Case A
          identity.user
        elsif (matched = User.find_by(email: profile.email))
          # Case B — email matches existing user
          unless profile.email_verified == true
            raise Auth::EmailMismatch,
                  "provider did not verify email=#{profile.email}"
          end
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
          raise NotImplementedError, "Case C — next task"
        end

      user.track_login!(identity)
      user
    end
  end
end
