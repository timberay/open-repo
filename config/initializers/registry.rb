Rails.application.configure do
  config.x.registry.admin_email = ENV.fetch("REGISTRY_ADMIN_EMAIL", nil)
end
