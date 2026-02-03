class RegistryConnectionTester
  class ConnectionTestResult
    attr_reader :success, :message, :response_time

    def initialize(success:, message:, response_time: nil)
      @success = success
      @message = message
      @response_time = response_time
    end

    def success?
      @success
    end
  end

  def self.test(url, username: nil, password: nil, timeout: 5)
    new(url, username: username, password: password, timeout: timeout).test
  end

  def initialize(url, username: nil, password: nil, timeout: 5)
    @url = url
    @username = username
    @password = password
    @timeout = timeout
  end

  def test
    start_time = Time.current

    connection = build_connection
    response = connection.get("/v2/")

    response_time = ((Time.current - start_time) * 1000).round(2)

    if response.status == 200
      ConnectionTestResult.new(
        success: true,
        message: "Successfully connected to registry (#{response_time}ms)",
        response_time: response_time
      )
    else
      ConnectionTestResult.new(
        success: false,
        message: "Registry returned status #{response.status}"
      )
    end
  rescue Faraday::UnauthorizedError
    ConnectionTestResult.new(
      success: false,
      message: "Authentication failed. Please check username and password."
    )
  rescue Faraday::TimeoutError
    ConnectionTestResult.new(
      success: false,
      message: "Connection timeout. Registry may be unreachable."
    )
  rescue Faraday::ConnectionFailed => e
    ConnectionTestResult.new(
      success: false,
      message: "Connection failed: #{e.message}"
    )
  rescue StandardError => e
    ConnectionTestResult.new(
      success: false,
      message: "Unexpected error: #{e.message}"
    )
  end

  private

  def build_connection
    Faraday.new(url: @url) do |f|
      f.request :authorization, :basic, @username, @password if @username && @password
      f.response :raise_error
      f.adapter Faraday.default_adapter
      f.options.timeout = @timeout
      f.options.open_timeout = @timeout
    end
  end
end
