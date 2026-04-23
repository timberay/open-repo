module Auth
  # Value object — normalized OAuth profile across providers.
  ProviderProfile = Data.define(:provider, :uid, :email, :email_verified, :name, :avatar_url)
end
