class TagsController < ApplicationController
  before_action :set_repository
  before_action :set_tag, only: [ :show, :destroy, :history ]
  before_action :authorize_delete!, only: [ :destroy ]

  def show
    @manifest = @tag.manifest
    @layers = @manifest.layers.includes(:blob).order(:position)
  end

  def destroy
    @repository.enforce_tag_protection!(@tag.name)

    TagEvent.create!(
      repository: @repository,
      tag_name: @tag.name,
      action: "delete",
      previous_digest: @tag.manifest.digest,
      actor: current_user.primary_identity.email,
      actor_identity_id: current_user.primary_identity_id,
      occurred_at: Time.current
    )
    @tag.destroy!
    redirect_to repository_path(@repository.name), notice: "Tag '#{@tag.name}' deleted."
  rescue Registry::TagProtected => e
    redirect_to repository_path(@repository.name),
      alert: "Tag '#{@tag.name}' is protected by policy '#{e.detail[:policy]}'. Change the repository's tag protection policy to delete it."
  end

  def history
    @events = TagEvent.where(repository: @repository, tag_name: @tag.name)
      .order(occurred_at: :desc)
      .page(params[:page]).per(25)
  end

  private

  def set_repository
    @repository = Repository.find_by!(name: params[:repository_name])
  end

  def set_tag
    @tag = @repository.tags.find_by!(name: params[:name])
  end

  def authorize_delete!
    authorize_for!(:delete)
  end
end
