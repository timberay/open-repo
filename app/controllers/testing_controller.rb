# Test-only helper — only mounted when Rails.env.test?.
class TestingController < ApplicationController
  skip_forgery_protection

  def sign_in
    session[:user_id] = params[:user_id].to_i
    head :ok
  end
end
