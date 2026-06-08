Rails.application.configure do
  config.x.registry.admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
  config.x.registry.anonymous_pull_enabled =
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("REGISTRY_ANONYMOUS_PULL", "true"))
end

# Opt-in sign-up restriction: comma-separated email domains allowed to sign in
# via OAuth. Empty (default) means any verified email may sign in. A value that
# is present but parses to no valid domains fails closed (raises at boot).
#
# Parsed in after_initialize so the autoloaded parser is available — autoloading
# is not yet active while config/initializers run.
Rails.application.config.after_initialize do
  Rails.application.config.x.registry.allowed_email_domains =
    Auth::AllowedEmailDomains.parse(ENV.fetch("REGISTRY_ALLOWED_EMAIL_DOMAINS", ""))
end
