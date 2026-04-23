Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           Rails.application.credentials.dig(:google_oauth, :client_id),
           Rails.application.credentials.dig(:google_oauth, :client_secret),
           {
             scope: "email,profile",
             prompt: "select_account",
             image_aspect_ratio: "square",
             image_size: 50,
             access_type: "online"
           }
end

OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.silence_get_warning = false

OmniAuth.config.on_failure = ->(env) {
  env["action_dispatch.request.path_parameters"] = { controller: "auth/sessions", action: "failure" }
  Auth::SessionsController.action(:failure).call(env)
}
