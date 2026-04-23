module RepositoryAuthorization
  extend ActiveSupport::Concern

  # Authorizes current_user to perform `action` on @repository.
  #
  # @param action [:read, :write, :delete]
  # @raise [Auth::Unauthenticated] if current_user is nil
  # @raise [Auth::ForbiddenAction]  if action is denied
  #
  # Note: @repository must be assigned before calling this method.
  # Note: rescue_from mappings are defined in each base controller (V2/Web).
  def authorize_for!(action)
    raise Auth::Unauthenticated if current_user.nil?

    identity = current_user.primary_identity

    allowed = case action
    when :read   then true  # Stage 3: repo visibility gate
    when :write  then @repository.writable_by?(identity)
    when :delete then @repository.deletable_by?(identity)
    end

    return if allowed

    raise Auth::ForbiddenAction.new(repository: @repository, action: action)
  end
end
