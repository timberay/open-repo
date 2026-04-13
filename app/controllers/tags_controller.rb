class TagsController < ApplicationController
  before_action :set_repository
  before_action :set_tag, only: [:show, :destroy, :history]

  def show
    @manifest = @tag.manifest
    @layers = @manifest.layers.includes(:blob).order(:position)
  end

  def destroy
    TagEvent.create!(
      repository: @repository,
      tag_name: @tag.name,
      action: 'delete',
      previous_digest: @tag.manifest.digest,
      actor: 'anonymous',
      occurred_at: Time.current
    )
    @tag.destroy!
    redirect_to repository_path(@repository.name), notice: "Tag '#{@tag.name}' deleted."
  end

  def history
    @events = TagEvent.where(repository: @repository, tag_name: @tag.name).order(occurred_at: :desc)
  end

  private

  def set_repository
    @repository = Repository.find_by!(name: params[:repository_name])
  end

  def set_tag
    @tag = @repository.tags.find_by!(name: params[:name])
  end
end
