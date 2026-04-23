module Auth
  class PatAuthenticator
    Result = Data.define(:user, :pat)

    # @param email     [String]
    # @param raw_token [String]
    # @return [Result]
    # @raise [Auth::PatInvalid]
    def call(email:, raw_token:)
      raise Auth::PatInvalid, "email blank" if email.blank?
      raise Auth::PatInvalid, "token blank" if raw_token.blank?

      pat = PersonalAccessToken.authenticate_raw(raw_token)
      raise Auth::PatInvalid, "unknown or inactive PAT" if pat.nil?

      user = pat.identity.user
      unless user.email.to_s.downcase == email.to_s.downcase
        raise Auth::PatInvalid, "email mismatch"
      end

      Result.new(user: user, pat: pat)
    end
  end
end
