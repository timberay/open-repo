class SessionCreator
  # @param profile [Auth::ProviderProfile]
  # @return [User]
  # @raise [Auth::InvalidProfile], [Auth::EmailMismatch]
  def call(profile)
    raise Auth::InvalidProfile, "profile email blank" if profile.email.blank?

    User.transaction do
      identity = Identity.find_by(provider: profile.provider, uid: profile.uid)
      user =
        if identity
          # Case A
          identity.user
        else
          raise NotImplementedError, "Case B/C — next task"
        end

      user.track_login!(identity)
      user
    end
  end
end
