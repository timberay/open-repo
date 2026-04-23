module Auth
  class GoogleAdapter
    # @param auth_hash [OmniAuth::AuthHash]
    # @return [Auth::ProviderProfile]
    # @raise [Auth::InvalidProfile]
    def to_profile(auth_hash)
      uid = auth_hash.uid.to_s
      email = auth_hash.info&.email.to_s

      raise Auth::InvalidProfile, "missing uid"   if uid.blank?
      raise Auth::InvalidProfile, "missing email" if email.blank?

      verified_raw = auth_hash.dig("extra", "raw_info", "email_verified") ||
                     auth_hash.dig(:extra, :raw_info, :email_verified)
      email_verified =
        case verified_raw
        when true, "true"   then true
        when false, "false" then false
        else nil
        end

      ProviderProfile.new(
        provider: auth_hash.provider,
        uid: uid,
        email: email.downcase,
        email_verified: email_verified,
        name: auth_hash.info&.name,
        avatar_url: auth_hash.info&.image
      )
    end
  end
end
