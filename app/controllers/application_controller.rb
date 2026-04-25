class ApplicationController < ActionController::Base
  include RepositoryAuthorization
  include Auth::SafeReturn

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :signed_in?

  rescue_from Auth::Unauthenticated, with: :handle_unauthenticated
  rescue_from Auth::ForbiddenAction, with: ->(e) {
    redirect_to repository_path(e.repository.name),
                alert: "You don't have permission to #{e.action} in '#{e.repository.name}'."
  }

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user =
      if session[:user_id]
        User.find_by(id: session[:user_id]).tap do |u|
          session.delete(:user_id) if u.nil?
        end
      end
  end

  def signed_in?
    current_user.present?
  end

  def handle_unauthenticated
    redirect_to_sign_in!
  end

  def redirect_to_sign_in!
    session[:return_to] = request.fullpath if request.get?
    redirect_to sign_in_path
  end
end
