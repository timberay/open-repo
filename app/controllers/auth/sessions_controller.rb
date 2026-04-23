class Auth::SessionsController < ApplicationController
  skip_forgery_protection only: [ :create ]

  def create
    auth_hash = request.env["omniauth.auth"] or
      raise Auth::InvalidProfile, "missing omniauth.auth env (middleware not engaged)"
    profile = adapter_for(provider_param).to_profile(auth_hash)
    user = Auth::SessionCreator.new.call(profile)
    reset_session
    session[:user_id] = user.id
    # Signed-in user sees their own email — intentional UX, not PII exposure.
    redirect_to root_path, notice: "Signed in as #{user.email}"
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
    strategy = params[:strategy].presence || "unknown"
    message  = params[:message].presence  || "failed"
    flash[:alert] = "Sign-in failed (#{strategy}: #{message})."
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out."
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
