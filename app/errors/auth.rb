module Auth
  class Error < StandardError; end

  # Stage 0: OAuth callback flow
  class InvalidProfile < Error; end
  class EmailMismatch  < Error; end
  class ProviderOutage < Error; end

  # Stage 1: PAT HTTP Basic auth (Registry V2)
  class Unauthenticated < Error; end # no/malformed Authorization header
  class PatInvalid      < Error; end # PAT not found / revoked / expired / email mismatch
end
