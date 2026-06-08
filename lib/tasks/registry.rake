namespace :registry do
  desc "Revoke active PATs whose owner email domain is not in REGISTRY_ALLOWED_EMAIL_DOMAINS"
  task revoke_disallowed_pats: :environment do
    allowed = Rails.configuration.x.registry.allowed_email_domains

    if allowed.blank?
      puts "REGISTRY_ALLOWED_EMAIL_DOMAINS is empty — no domain restriction, nothing to revoke."
      next
    end

    revoked = PersonalAccessToken.revoke_disallowed!(allowed)

    puts "Allowlist: #{allowed.join(', ')}"
    puts "Revoked #{revoked.size} PAT(s) from disallowed domains."
    revoked.each do |pat|
      puts "  - #{pat.identity.user.email}  (#{pat.prefix}…, name: #{pat.name})"
    end
  end
end
