class RepositoriesController < ApplicationController
  def index
    @repositories = Repository.all.order(updated_at: :desc)

    if params[:q].present?
      q = "%#{params[:q]}%"
      @repositories = @repositories.where('name LIKE ? OR description LIKE ? OR maintainer LIKE ?', q, q, q)
    end

    case params[:sort]
    when 'name' then @repositories = @repositories.reorder(:name)
    when 'size' then @repositories = @repositories.reorder(total_size: :desc)
    when 'pulls'
      @repositories = @repositories
        .left_joins(:manifests)
        .group(:id)
        .reorder(Arel.sql('COALESCE(SUM(manifests.pull_count), 0) DESC'))
    end
  end

  def show
    @repository = Repository.find_by!(name: params[:name])
    @tags = @repository.tags.includes(:manifest).order(updated_at: :desc)
  end

  def update
    @repository = Repository.find_by!(name: params[:name])
    if @repository.update(repository_params)
      redirect_to repository_path(@repository.name), notice: 'Repository updated.'
    else
      @tags = @repository.tags.includes(:manifest).order(updated_at: :desc)
      flash.now[:alert] = @repository.errors.full_messages.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    repository = Repository.find_by!(name: params[:name])

    repository.manifests.includes(layers: :blob).find_each do |manifest|
      manifest.layers.each { |layer| layer.blob.decrement!(:references_count) }
    end

    repository.destroy!
    redirect_to root_path, notice: "Repository '#{repository.name}' deleted."
  end

  private

  def repository_params
    params.expect(repository: [:description, :maintainer, :tag_protection_policy, :tag_protection_pattern])
  end
end
