# frozen_string_literal: true

# E2E seed helper — run via `bin/rails runner e2e/support/seed.rb`.
#
# Creates (or refreshes, idempotently) the User + Identity + Repository +
# Manifest + Tag graph that Playwright specs rely on. Prints a JSON payload
# with the seeded `user_id` on the last line so JS test helpers can parse it.
#
# Safe to call before every test. Re-running does NOT duplicate rows;
# find_or_create_by! is used throughout and repositories / tags are touched
# to ensure the seed state matches expectations on each invocation.

require "json"

raise "refusing to seed outside development/test" unless Rails.env.development? || Rails.env.test?

owner_user = User.find_or_create_by!(email: "e2e-owner@example.test") do |u|
  u.admin = false
end

owner_identity = Identity.find_or_create_by!(provider: "google_oauth2", uid: "e2e-owner-uid") do |i|
  i.user = owner_user
  i.email = owner_user.email
  i.email_verified = true
  i.name = "E2E Owner"
end

if owner_user.primary_identity_id != owner_identity.id
  owner_user.update!(primary_identity: owner_identity)
end

# ---------------------------------------------------------------------------
# General-purpose repositories for list/search/sort/tag-details specs.
# Names are chosen so the `search.spec.js` "backend" query matches at least
# one result, and sort order is deterministic enough to assert against.
# ---------------------------------------------------------------------------
seed_repos = [
  { name: "backend-api",  description: "Backend API service",    maintainer: "Platform Team" },
  { name: "frontend-web", description: "Frontend web client",    maintainer: "Web Team" },
  { name: "worker-jobs",  description: "Background worker jobs", maintainer: "Platform Team" }
]

seed_repos.each do |attrs|
  repo = Repository.find_or_create_by!(name: attrs[:name]) do |r|
    r.owner_identity = owner_identity
    r.description    = attrs[:description]
    r.maintainer     = attrs[:maintainer]
  end

  # Ensure existing seed rows have current values and valid ownership.
  repo.update!(
    owner_identity: owner_identity,
    description: attrs[:description],
    maintainer: attrs[:maintainer]
  )

  manifest = repo.manifests.find_or_create_by!(digest: "sha256:e2e-#{attrs[:name]}") do |m|
    m.media_type = "application/vnd.docker.distribution.manifest.v2+json"
    m.payload    = "{}"
    m.size       = 1024
  end

  repo.tags.find_or_create_by!(name: "v1.0.0") { |t| t.manifest = manifest }
  repo.tags.find_or_create_by!(name: "latest") { |t| t.manifest = manifest }
end

puts({ user_id: owner_user.id, owner_identity_id: owner_identity.id }.to_json)
