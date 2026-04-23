Rails.application.configure do
  config.x.registry.admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
  config.x.registry.anonymous_pull_enabled =
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("REGISTRY_ANONYMOUS_PULL", "true"))
end
