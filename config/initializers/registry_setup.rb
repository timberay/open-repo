Rails.application.config.after_initialize do
  # Skip local registry scanning in test environment, when using mock registry, or in E2E tests
  next if Rails.env.test?
  next if Rails.application.config.use_mock_registry
  next unless ActiveRecord::Base.connection.table_exists?(:registries)

  begin
    discovered_count = LocalRegistryScanner.new.scan_and_register!
    Rails.logger.info "Local registry scan complete: #{discovered_count} registries discovered" if discovered_count > 0

    RegistryHealthCheckService.check_all!
  rescue StandardError => e
    Rails.logger.warn "Registry setup failed: #{e.message}"
  end
end
