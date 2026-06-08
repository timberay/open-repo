module Auth
  # Parsing + normalization for the OAuth sign-up domain allowlist
  # (env `REGISTRY_ALLOWED_EMAIL_DOMAINS`). Both the config value and the
  # email-derived domain are canonicalized the same way so comparisons match.
  #
  # Scope: ASCII / punycode domains only. Unicode IDNA normalization is not
  # performed — provide already-encoded (punycode) domains for non-ASCII.
  module AllowedEmailDomains
    module_function

    # Comma-separated env string → normalized domain list.
    # Fails closed: a value that is present but yields no valid domains raises,
    # so a malformed setting can never silently degrade to "allow everyone".
    def parse(raw)
      domains = raw.to_s.split(",").filter_map { |entry| normalize(entry) }

      if raw.to_s.strip.present? && domains.empty?
        raise ArgumentError,
              "REGISTRY_ALLOWED_EMAIL_DOMAINS is set but contains no valid domains"
      end

      domains
    end

    # Email → normalized domain, or nil when the address is malformed.
    # Requires exactly one "@" so spoofs like "a@evil.com@allowed.com" and
    # bare strings without "@" never resolve to an allowed domain.
    def domain_for(email)
      parts = email.to_s.split("@")
      return nil unless parts.length == 2

      normalize(parts.last)
    end

    def normalize(value)
      value.to_s.strip.downcase.delete_suffix(".").presence
    end
  end
end
