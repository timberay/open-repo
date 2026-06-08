module Auth
  # Parsing + normalization for the OAuth sign-up domain allowlist
  # (env `REGISTRY_ALLOWED_EMAIL_DOMAINS`). Both the config value and the
  # email-derived domain are canonicalized the same way so comparisons match.
  #
  # Scope: ASCII / punycode domains only. Unicode IDNA normalization is not
  # performed — provide already-encoded (punycode) domains for non-ASCII.
  module AllowedEmailDomains
    module_function

    # Characters that can never appear in a bare domain — catches operator
    # typos like "http://timberay.com", "a.com b.com", or embedded newlines.
    INVALID_DOMAIN_CHARS = %r{[\s@/]}

    # Comma-separated env string → normalized domain list.
    # Fails closed: a value that is present but yields no valid domains, or that
    # contains a malformed domain token, raises — so a bad setting can never
    # silently degrade to "allow everyone" or "deny the intended org".
    def parse(raw)
      tokens = raw.to_s.split(",").filter_map { |entry| normalize(entry) }
      return [] if raw.to_s.strip.blank?

      invalid = tokens.reject { |token| valid_domain?(token) }
      if tokens.empty? || invalid.any?
        raise ArgumentError,
              "REGISTRY_ALLOWED_EMAIL_DOMAINS is set but has no valid domains " \
              "(invalid: #{invalid.inspect})"
      end

      tokens
    end

    # Email → normalized domain, or nil when the address is malformed.
    # Splits with -1 to keep trailing empty fields, then requires exactly two
    # non-empty parts so spoofs like "a@evil.com@allowed.com",
    # "user@allowed.com@", "@allowed.com", and bare strings without "@" never
    # resolve to an allowed domain.
    def domain_for(email)
      local, domain, extra = email.to_s.split("@", -1)
      return nil unless extra.nil?
      return nil if local.to_s.empty?

      normalize(domain)
    end

    def normalize(value)
      value.to_s.strip.downcase.delete_suffix(".").presence
    end

    def valid_domain?(token)
      !token.match?(INVALID_DOMAIN_CHARS)
    end
  end
end
