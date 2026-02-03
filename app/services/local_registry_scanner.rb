class LocalRegistryScanner
  DEFAULT_PORTS = (5000..5010).to_a.freeze
  DEFAULT_TIMEOUT = 2

  def self.scan(ports: DEFAULT_PORTS, timeout: DEFAULT_TIMEOUT)
    new(ports: ports, timeout: timeout).scan
  end

  def initialize(ports: DEFAULT_PORTS, timeout: DEFAULT_TIMEOUT)
    @ports = ports
    @timeout = timeout
  end

  def scan
    discovered_registries = []

    @ports.each do |port|
      url = "http://localhost:#{port}"

      result = RegistryConnectionTester.test(url, timeout: @timeout)

      if result.success?
        discovered_registries << {
          name: "Local Registry (#{port})",
          url: url,
          port: port,
          response_time: result.response_time
        }
      end
    end

    discovered_registries
  end

  def scan_and_register!
    discovered = scan

    discovered.each do |registry_info|
      next if Registry.exists?(url: registry_info[:url])

      Registry.create!(
        name: registry_info[:name],
        url: registry_info[:url],
        is_active: true,
        is_default: false,
        last_connected_at: Time.current
      )

      Rails.logger.info "Auto-registered local registry: #{registry_info[:name]} at #{registry_info[:url]}"
    end

    discovered.size
  end
end
