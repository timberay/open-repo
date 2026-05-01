module Settings
  class TokensController < ApplicationController
    before_action :ensure_current_user

    def index
      @tokens = current_identity.personal_access_tokens.order(created_at: :desc)
    end

    def create
      raw = PersonalAccessToken.generate_raw
      pat = current_identity.personal_access_tokens.new(
        name: pat_params[:name],
        kind: pat_params[:kind].presence || "cli",
        token_digest: Digest::SHA256.hexdigest(raw),
        prefix: PersonalAccessToken.prefix_for(raw),
        expires_at: parse_expires_in(pat_params[:expires_in_days])
      )
      if pat.save
        flash[:raw_token] = raw
        redirect_to settings_tokens_path
      else
        @tokens = current_identity.personal_access_tokens.order(created_at: :desc)
        @error = pat.errors.full_messages.to_sentence
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      pat = current_identity.personal_access_tokens.find_by(id: params[:id])
      if pat.nil?
        head :not_found
        return
      end
      pat.revoke!
      redirect_to settings_tokens_path, notice: "Token revoked."
    end

    private

    def ensure_current_user
      return if signed_in?
      redirect_to_sign_in!
    end

    def current_identity
      current_user.primary_identity
    end

    def pat_params
      params.expect(personal_access_token: [ :name, :kind, :expires_in_days ])
    end

    def parse_expires_in(days_str)
      return nil if days_str.blank?
      days = Integer(days_str, exception: false)
      return nil if days.nil? || days <= 0
      days.days.from_now
    end
  end
end
