require 'rails_helper'

RSpec.describe 'Repositories', type: :request do
  let!(:repo) { Repository.create!(name: 'test-repo', description: 'Test', maintainer: 'Team A') }
  let!(:manifest) { Manifest.create!(repository: repo, digest: 'sha256:abc', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 100) }
  let!(:tag) { Tag.create!(repository: repo, manifest: manifest, name: 'v1.0.0') }

  describe 'GET /' do
    it 'lists repositories' do
      get root_path
      expect(response).to have_http_status(200)
      expect(response.body).to include('test-repo')
    end

    it 'searches by name' do
      get root_path, params: { q: 'test' }
      expect(response.body).to include('test-repo')
    end
  end

  describe 'GET /repositories/:name' do
    it 'shows repository details' do
      get repository_path('test-repo')
      expect(response).to have_http_status(200)
      expect(response.body).to include('v1.0.0')
    end
  end

  describe 'PATCH /repositories/:name' do
    it 'updates description' do
      patch repository_path('test-repo'), params: { repository: { description: 'Updated' } }
      expect(response).to redirect_to(repository_path('test-repo'))
      expect(repo.reload.description).to eq('Updated')
    end
  end

  describe 'DELETE /repositories/:name' do
    it 'destroys repository' do
      delete repository_path('test-repo')
      expect(response).to redirect_to(root_path)
      expect(Repository.find_by(name: 'test-repo')).to be_nil
    end
  end

  describe 'Protected tag badge rendering' do
    let!(:protected_repo) { Repository.create!(name: 'protected-repo', tag_protection_policy: 'semver') }
    let!(:protected_manifest) { Manifest.create!(repository: protected_repo, digest: 'sha256:def', media_type: 'application/vnd.docker.distribution.manifest.v2+json', payload: '{}', size: 200) }
    let!(:protected_tag) { Tag.create!(repository: protected_repo, manifest: protected_manifest, name: 'v1.0.0') }

    it 'renders protected badge with lock-closed heroicon, no emoji, text-sm' do
      get repository_path('protected-repo')
      expect(response).to be_successful
      # Assert emoji is NOT rendered
      expect(response.body).not_to include("🔒")
      # Assert lock-closed heroicon is rendered (check for SVG with data-icon attribute or path signature)
      expect(response.body).to match(/lock-closed|M16\.5 10\.5V6\.75/)
      # Assert badge has text-sm (base class of BadgeComponent)
      expect(response.body).to match(/class="[^"]*text-sm[^"]*"/)
    end
  end

  describe 'Save button icon' do
    it 'renders a heroicon inside the Save submit button' do
      get repository_path('test-repo')
      expect(response).to be_successful
      # Parse the Save button and assert it contains an <svg> child
      # The ButtonComponent with icon adds gap-2 and emits <svg class="w-5 h-5">…</svg> before text
      # Assert: Save button has SVG before "Save" text
      expect(response.body).to match(/<button[^>]*type="submit"[^>]*>\s*<svg[^>]*>.*?<\/svg>\s*Save\s*<\/button>/m)
    end
  end

  describe 'Destructive actions grounding' do
    it 'wraps Delete Repository in a labeled Danger Zone section' do
      get repository_path('test-repo')
      expect(response).to be_successful
      # Previously the Delete Repository button floated in a flex justify-end div
      # with no container or warning label. Require a labeled section.
      expect(response.body).to match(/Danger Zone/)
      # The button itself must still be present.
      expect(response.body).to include('Delete Repository')
      # And the section should carry a top border (grounding).
      danger_section = response.body.match(/<section[^>]*aria-labelledby="danger-zone"[^>]*>[\s\S]*?<\/section>/m)
      expect(danger_section).not_to be_nil, 'expected <section aria-labelledby="danger-zone">'
      expect(danger_section[0]).to include('border-t')
      expect(danger_section[0]).to include('Delete Repository')
    end
  end

  describe 'Header touch targets (a11y)' do
    it 'gives the theme toggle and Help link at least 44px tap height' do
      get root_path
      expect(response).to be_successful
      # Theme toggle: p-2 + w-5 h-5 svg = 36px tap target. Bump padding to p-3 → 44px.
      toggle = response.body.match(/<button[^>]*data-action="click->theme#toggle"[^>]*class="([^"]*)"/m)
      expect(toggle).not_to be_nil, 'expected theme toggle button'
      expect(toggle[1]).to include('p-3')
      expect(toggle[1]).not_to match(/\bp-2\b/)

      # Help link: inline-flex + text-sm with no vertical padding ≈ 20px. Require a
      # min-h-11 (44px) minimum to guarantee WCAG mobile touch-target size.
      # Rails' link_to emits attributes in an unspecified order, so match either class-first
      # or href-first forms.
      help_link = response.body.match(
        /<a\s+(?:class="([^"]*)"[^>]*href="\/help"|href="\/help"[^>]*class="([^"]*)")/m
      )
      expect(help_link).not_to be_nil, 'expected Help link'
      help_classes = help_link[1] || help_link[2]
      expect(help_classes).to include('min-h-11')
    end
  end

  describe 'Index page heading' do
    it 'renders a single H1 with the page name for wayfinding' do
      get root_path
      expect(response).to be_successful
      # There were zero <h1> on the index before; only <h3> per card.
      # A page-level <h1> is table stakes for trunk-test wayfinding.
      h1_matches = response.body.scan(/<h1\b[^>]*>([\s\S]*?)<\/h1>/m).flatten
      expect(h1_matches.length).to eq(1), "expected exactly 1 <h1>, got #{h1_matches.length}"
      expect(h1_matches.first).to match(/Repositories/)
    end
  end

  describe 'Repository card (index)' do
    let!(:no_maintainer_repo) { Repository.create!(name: 'no-maintainer', maintainer: nil) }

    it 'does not render a redundant "Docker Image" badge on each card' do
      get root_path
      expect(response).to be_successful
      # Every card currently renders a "Docker Image" info pill. It is pure noise
      # (every artifact in this registry is a Docker image by definition) and it
      # creates the card-height inconsistency called out in FINDING-007.
      expect(response.body).not_to include('Docker Image')
    end

    it 'renders the maintainer text with contrast that meets WCAG AA on both themes' do
      get root_path
      expect(response).to be_successful
      # Old: text-slate-400 dark:text-slate-500 — ~2.5:1 on dark surfaces, fails AA (4.5:1).
      # New target: text-slate-600 dark:text-slate-300 — comfortably >4.5:1 on both.
      test_repo_card = response.body.match(
        /<a[^>]*href="\/repositories\/test-repo"[\s\S]*?<\/a>/m
      )
      expect(test_repo_card).not_to be_nil
      maintainer_span = test_repo_card[0].match(/<span[^>]*class="([^"]*)"[^>]*>\s*Team A\s*<\/span>/m)
      expect(maintainer_span).not_to be_nil, 'expected maintainer span with "Team A"'
      classes = maintainer_span[1]
      expect(classes).to include('text-slate-600')
      expect(classes).to include('dark:text-slate-300')
      expect(classes).not_to include('text-slate-400')
      expect(classes).not_to include('dark:text-slate-500')
    end

    it 'omits the card bottom row entirely when the repository has no maintainer' do
      get root_path
      expect(response).to be_successful
      # After removing the Docker Image pill, the bottom <div class="...border-t...">
      # should not render for repositories with no maintainer — otherwise we leak
      # an empty bordered row under the card.
      no_maintainer_card = response.body.match(
        /<a[^>]*href="\/repositories\/no-maintainer"[\s\S]*?<\/a>/m
      )
      expect(no_maintainer_card).not_to be_nil
      expect(no_maintainer_card[0]).not_to include('border-t')
    end
  end

  describe 'Tag count badge variant' do
    it 'renders the "N tags" count with a neutral variant, not success (green)' do
      get repository_path('test-repo')
      expect(response).to be_successful
      # The tag count is a plain number; success/green implies a positive state
      # outcome, which is semantically wrong for a count.
      count_badge = response.body.match(
        /<span[^>]*class="([^"]*)"[^>]*>\s*(?:<svg[^>]*>.*?<\/svg>\s*)?1 tags\s*<\/span>/m
      )
      expect(count_badge).not_to be_nil, 'expected "1 tags" badge'
      badge_classes = count_badge[1]
      expect(badge_classes).not_to match(/bg-green-|text-green-/), 'tag count badge should not use success (green) colors'
      expect(badge_classes).to include('bg-slate-200').or include('bg-slate-700')
    end
  end

  describe 'Edit details disclosure marker' do
    it 'hides the native disclosure triangle so only the custom chevron shows' do
      get repository_path('test-repo')
      expect(response).to be_successful
      # The <summary> for "Edit description & maintainer" uses a custom SVG chevron.
      # Without suppressing the native marker, browsers render BOTH the default triangle
      # and our chevron (double-icon bug). Assert list-none + webkit-marker hide is applied.
      summary_match = response.body.match(/<summary([^>]*class="[^"]*")[^>]*>(?:.(?!<\/summary>))*?Edit description/m)
      expect(summary_match).not_to be_nil, 'expected summary with "Edit description" label'
      summary_classes = summary_match[1]
      expect(summary_classes).to include('list-none')
      expect(summary_classes).to include('[&::-webkit-details-marker]:hidden')
    end
  end

  describe 'PATCH /repositories/:name with tag protection fields' do
    let!(:protection_repo) { Repository.create!(name: 'example') }

    it 'persists tag_protection_policy when set to semver' do
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'semver' } }
      expect(protection_repo.reload.tag_protection_policy).to eq('semver')
    end

    it 'persists tag_protection_pattern when policy is custom_regex' do
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '^release-\d+$' } }
      expect(protection_repo.reload.tag_protection_policy).to eq('custom_regex')
      expect(protection_repo.reload.tag_protection_pattern).to eq('^release-\d+$')
    end

    it 'clears pattern when policy reverts from custom_regex' do
      protection_repo.update!(tag_protection_policy: 'custom_regex', tag_protection_pattern: '^v.+$')
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'semver', tag_protection_pattern: '^v.+$' } }
      expect(protection_repo.reload.tag_protection_pattern).to be_nil
    end

    it 'rejects invalid regex' do
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '[unclosed' } }
      expect(protection_repo.reload.tag_protection_policy).to eq('none')
    end

    it 'renders 422 with the validation message when regex is invalid (no 500)' do
      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '[unclosed' } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/is not a valid regex/)
    end

    it 'does not crash when the invalid in-memory state touches tags in the view' do
      protection_repo.manifests.create!(
        digest: 'sha256:showcrash', media_type: 'application/vnd.docker.distribution.manifest.v2+json',
        payload: '{}', size: 2
      ).tap { |m| protection_repo.tags.create!(name: 'v1.0.0', manifest: m) }

      patch "/repositories/#{protection_repo.name}",
        params: { repository: { tag_protection_policy: 'custom_regex', tag_protection_pattern: '[unclosed' } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('v1.0.0')
    end
  end

  describe 'Mobile tag Delete button icon' do
    it 'renders a trash heroicon in BOTH desktop and mobile Delete buttons' do
      get repository_path('test-repo')
      expect(response).to be_successful
      # Extract all tag-delete forms (action contains /tags/)
      tag_delete_forms = response.body.scan(/<form[^>]*action="[^"]*\/tags\/[^"]*"[^>]*>.*?<\/form>/m)
      expect(tag_delete_forms.size).to eq(2), "Expected 2 tag-delete forms (desktop + mobile), got #{tag_delete_forms.size}"
      # Both forms must contain a trash heroicon SVG
      forms_with_svg = tag_delete_forms.count { |form| form.include?('<svg') }
      expect(forms_with_svg).to eq(2), "Expected both forms to have a trash heroicon SVG, but only #{forms_with_svg} did"
    end
  end
end
