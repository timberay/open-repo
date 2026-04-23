module Auth
  class Error < StandardError; end

  # Stage 0: OAuth callback flow
  class InvalidProfile < Error; end
  class EmailMismatch  < Error; end
  class ProviderOutage < Error; end
end
