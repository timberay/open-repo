class Auth::SessionsController < ApplicationController
  ALLOWED_FAILURE_MESSAGES = %w[email_mismatch invalid_profile provider_outage failed].freeze
  ALLOWED_STRATEGIES        = %w[google_oauth2].freeze

  skip_forgery_protection only: [ :create ]

  def new
    redirect_to(root_path) and return if signed_in?
  end

  def create
    auth_hash = request.env["omniauth.auth"] or
      raise Auth::InvalidProfile, "missing omniauth.auth env (middleware not engaged)"
    profile = adapter_for(provider_param).to_profile(auth_hash)
    user = Auth::SessionCreator.new.call(profile)

    # Pull return_to BEFORE reset_session wipes it; validate before trusting it.
    return_to = session[:return_to]
    reset_session
    session[:user_id] = user.id
    destination = safe_return_to(return_to) || root_path
    # Signed-in user sees their own email — intentional UX, not PII exposure.
    redirect_to destination, notice: "Signed in as #{user.email}"
  rescue Auth::EmailMismatch => e
    Rails.logger.warn("auth: email mismatch (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "email_mismatch")
  rescue Auth::InvalidProfile => e
    Rails.logger.warn("auth: invalid profile (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "invalid_profile")
  rescue Auth::ProviderOutage => e
    Rails.logger.warn("auth: provider outage (#{e.message})")
    redirect_to auth_failure_path(strategy: provider_param, message: "provider_outage")
  end

  def failure
    strategy = ALLOWED_STRATEGIES.include?(params[:strategy]) ? params[:strategy] : "unknown"
    message  = ALLOWED_FAILURE_MESSAGES.include?(params[:message]) ? params[:message] : "failed"
    flash[:alert] = "Sign-in failed (#{strategy}: #{message})."
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to sign_in_path, notice: "Signed out."
  end

  private

  def provider_param
    params[:provider].presence || request.path_parameters[:provider] || "google_oauth2"
  end

  def adapter_for(provider)
    case provider
    when "google_oauth2" then Auth::GoogleAdapter.new
    else raise Auth::InvalidProfile, "unsupported provider: #{provider}"
    end
  end
end
