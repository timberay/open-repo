class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :signed_in?

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
end
