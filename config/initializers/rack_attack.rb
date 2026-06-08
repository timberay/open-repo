class Rack::Attack
  # Per-minute write budget for the V2 API. The default is generous enough for
  # a large multi-layer push (a 12-layer push is ~37 write requests) plus
  # several concurrent CI pushers behind one shared egress IP; override with
  # REGISTRY_V2_WRITE_LIMIT for ops tuning.
  def self.v2_write_limit
    Integer(ENV.fetch("REGISTRY_V2_WRITE_LIMIT", "600"))
  end

  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    if req.post? && req.path.start_with?("/auth/")
      req.ip
    end
  end

  # Throttle V2 writes (everything but GET/HEAD). Key on the authenticated PAT
  # so a shared NAT / CI egress IP does not collapse every pusher into one
  # budget mid-push; unauthenticated writes fall back to the client IP.
  throttle("v2_protected", limit: ->(_req) { Rack::Attack.v2_write_limit }, period: 1.minute) do |req|
    if req.path.start_with?("/v2/") && !(req.get? || req.head?)
      auth = req.get_header("HTTP_AUTHORIZATION")
      auth.present? ? "auth:#{Digest::SHA256.hexdigest(auth)}" : "ip:#{req.ip}"
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
