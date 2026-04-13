class HelpController < ApplicationController
  def show
    @registry_host = Rails.configuration.registry_host
  end
end
