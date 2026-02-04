class RegistryHealthCheckService
  def self.check_all!
    new.check_all!
  end

  def check_all!
    Registry.all.find_each do |registry|
      check_registry(registry)
    end
  end

  private

  def check_registry(registry)
    result = RegistryConnectionTester.test(
      registry.url,
      username: registry.username,
      password: registry.password,
      timeout: 2
    )

    if result.success?
      registry.update!(
        is_active: true,
        last_connected_at: Time.current
      )
    else
      registry.update!(is_active: false)
      Rails.logger.warn "Registry [#{registry.name}] at #{registry.url} is unreachable. Marked as inactive. Error: #{result.message}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to health check registry [#{registry.name}]: #{e.message}"
    registry.update(is_active: false) if registry.persisted?
  end
end
