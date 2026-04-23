module Auth
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
                    "provider did not verify identity=#{profile.provider}:#{profile.uid}"
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
            # Case C — brand-new user
            unless profile.email_verified == true
              raise Auth::EmailMismatch,
                    "provider did not verify identity=#{profile.provider}:#{profile.uid}"
            end
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
  end
end
