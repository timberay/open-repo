class RegistriesController < ApplicationController
  before_action :set_registry, only: [ :edit, :update, :destroy, :switch, :test_connection ]

  def index
    @registries = Registry.all.order(is_default: :desc, name: :asc)
    @env_registry = env_registry_config
  end

  def new
    @registry = Registry.new
  end

  def create
    @registry = Registry.new(registry_params)

    if @registry.save
      redirect_to registries_path, notice: "Registry was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @registry.update(registry_params)
      redirect_to registries_path, notice: "Registry was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @registry.id == session[:current_registry_id]
      session.delete(:current_registry_id)
    end

    @registry.destroy
    redirect_to registries_path, notice: "Registry was successfully deleted."
  end

  def switch
    session[:current_registry_id] = @registry.id
    redirect_to root_path, notice: "Switched to #{@registry.name}"
  end

  def switch_to_env
    session.delete(:current_registry_id)
    redirect_to root_path, notice: "Switched to [ENV] Default Registry"
  end

  def test_connection
    result = RegistryConnectionTester.test(
      @registry.url,
      username: @registry.username,
      password: @registry.password
    )

    if result.success?
      @registry.update(last_connected_at: Time.current)
    end

    respond_to do |format|
      format.json { render json: { success: result.success?, message: result.message, response_time: result.response_time } }
      format.turbo_stream {
        @result = result
      }
    end
  end

  private

  def set_registry
    @registry = Registry.find(params[:id])
  end

  def registry_params
    params.require(:registry).permit(:name, :url, :username, :password, :is_default, :is_active)
  end

  def env_registry_config
    return nil unless Rails.application.config.registry_url.present?

    {
      name: "[ENV] Default Registry",
      url: Rails.application.config.registry_url,
      username: Rails.application.config.registry_username,
      from_env: true
    }
  end
end
