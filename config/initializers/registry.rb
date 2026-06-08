Rails.application.configure do
  config.x.registry.admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
  config.x.registry.anonymous_pull_enabled =
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("REGISTRY_ANONYMOUS_PULL", "true"))

  # Opt-in sign-up restriction: comma-separated email domains allowed to sign in
  # via OAuth. Empty (default) means any verified email may sign in.
  config.x.registry.allowed_email_domains =
    ENV.fetch("REGISTRY_ALLOWED_EMAIL_DOMAINS", "")
       .split(",")
       .filter_map { |domain| domain.strip.downcase.presence }
end
