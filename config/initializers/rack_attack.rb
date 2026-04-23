class Rack::Attack
  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    if req.post? && req.path.start_with?("/auth/")
      req.ip
    end
  end

  throttle("v2_protected_by_ip", limit: 30, period: 1.minute) do |req|
    if req.path.start_with?("/v2/") && !(req.get? || req.head?)
      req.ip
    end
  end

  self.throttled_responder = lambda do |_req|
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => "60" },
      [ { errors: [ { code: "TOO_MANY_REQUESTS", message: "rate limited" } ] }.to_json ]
    ]
  end
end
