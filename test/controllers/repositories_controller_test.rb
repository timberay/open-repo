require "test_helper"

class RepositoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @repo = Repository.create!(name: "test-repo", description: "Test", maintainer: "Team A", owner_identity: identities(:tonny_google))
    @manifest = Manifest.create!(repository: @repo, digest: "sha256:abc", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 100)
    @tag = Tag.create!(repository: @repo, manifest: @manifest, name: "v1.0.0")
  end

  test "GET / lists repositories" do
    get root_path
    assert_response 200
    assert_includes response.body, "test-repo"
  end

  test "GET / searches by name" do
    get root_path, params: { q: "test" }
    assert_includes response.body, "test-repo"
  end

  test "GET /repositories/:name shows repository details" do
    get repository_path("test-repo")
    assert_response 200
    assert_includes response.body, "v1.0.0"
  end

  test "PATCH /repositories/:name updates description" do
    patch repository_path("test-repo"), params: { repository: { description: "Updated" } }
    assert_redirected_to repository_path("test-repo")
    assert_equal "Updated", @repo.reload.description
  end

  test "DELETE /repositories/:name destroys repository" do
    @repo.update!(owner_identity: identities(:tonny_google))
    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    delete repository_path("test-repo")
    assert_redirected_to root_path
    assert_nil Repository.find_by(name: "test-repo")
  end

  test "renders protected badge with lock-closed heroicon, no emoji, text-sm" do
    protected_repo = Repository.create!(name: "protected-repo", tag_protection_policy: "semver", owner_identity: identities(:tonny_google))
    protected_manifest = Manifest.create!(repository: protected_repo, digest: "sha256:def", media_type: "application/vnd.docker.distribution.manifest.v2+json", payload: "{}", size: 200)
    Tag.create!(repository: protected_repo, manifest: protected_manifest, name: "v1.0.0")

    get repository_path("protected-repo")
    assert_response :success
    assert_no_match(/🔒/, response.body)
    assert_match(/lock-closed|M16\.5 10\.5V6\.75/, response.body)
    assert_match(/class="[^"]*text-sm[^"]*"/, response.body)
  end

  test "renders a heroicon inside the Save submit button" do
    get repository_path("test-repo")
    assert_response :success
    assert_match(/<button[^>]*type="submit"[^>]*>\s*<svg[^>]*>.*?<\/svg>\s*Save\s*<\/button>/m, response.body)
  end

  test "keeps the command on one line and scrolls horizontally, never breaking mid-URL" do
    get repository_path("test-repo")
    assert_response :success
    pull_code = response.body.match(/<code[^>]*class="([^"]*)"[^>]*>docker pull/m)
    assert pull_code, "expected <code> with docker pull"
    classes = pull_code[1]
    assert_no_match(/break-all/, classes)
    assert_includes classes, "whitespace-nowrap"
    assert_includes classes, "overflow-x-auto"
  end

  test "wraps Delete Repository in a labeled Danger Zone section" do
    get repository_path("test-repo")
    assert_response :success
    assert_match(/Danger Zone/, response.body)
    assert_includes response.body, "Delete Repository"
    danger_section = response.body.match(/<section[^>]*aria-labelledby="danger-zone"[^>]*>[\s\S]*?<\/section>/m)
    assert danger_section, "expected <section aria-labelledby=\"danger-zone\">"
    assert_includes danger_section[0], "border-t"
    assert_includes danger_section[0], "Delete Repository"
  end

  test "gives the theme toggle and Help link at least 44px tap height" do
    get root_path
    assert_response :success
    toggle = response.body.match(/<button[^>]*data-action="click->theme#toggle"[^>]*class="([^"]*)"/m)
    assert toggle, "expected theme toggle button"
    assert_includes toggle[1], "p-3"
    assert_no_match(/\bp-2\b/, toggle[1])

    help_link = response.body.match(
      /<a\s+(?:class="([^"]*)"[^>]*href="\/help"|href="\/help"[^>]*class="([^"]*)")/m
    )
    assert help_link, "expected Help link"
    help_classes = help_link[1] || help_link[2]
    assert_includes help_classes, "min-h-11"
  end

  test "renders a single H1 with the page name for wayfinding" do
    get root_path
    assert_response :success
    h1_matches = response.body.scan(/<h1\b[^>]*>([\s\S]*?)<\/h1>/m).flatten
    assert_equal 1, h1_matches.length, "expected exactly 1 <h1>, got #{h1_matches.length}"
    assert_match(/Repositories/, h1_matches.first)
  end

  test "does not render a redundant 'Docker Image' badge on each card" do
    get root_path
    assert_response :success
    assert_no_match(/Docker Image/, response.body)
  end

  test "renders the maintainer text with contrast that meets WCAG AA on both themes" do
    get root_path
    assert_response :success
    test_repo_card = response.body.match(
      /<a[^>]*href="\/repositories\/test-repo"[\s\S]*?<\/a>/m
    )
    assert test_repo_card
    maintainer_span = test_repo_card[0].match(/<span[^>]*class="([^"]*)"[^>]*>\s*Team A\s*<\/span>/m)
    assert maintainer_span, "expected maintainer span with \"Team A\""
    classes = maintainer_span[1]
    assert_includes classes, "text-slate-600"
    assert_includes classes, "dark:text-slate-300"
    assert_no_match(/text-slate-400/, classes)
    assert_no_match(/dark:text-slate-500/, classes)
  end

  test "omits the card bottom row entirely when the repository has no maintainer" do
    Repository.create!(name: "no-maintainer", maintainer: nil, owner_identity: identities(:tonny_google))
    get root_path
    assert_response :success
    no_maintainer_card = response.body.match(
      /<a[^>]*href="\/repositories\/no-maintainer"[\s\S]*?<\/a>/m
    )
    assert no_maintainer_card
    assert_no_match(/border-t/, no_maintainer_card[0])
  end

  test "renders the 'N tags' count with a neutral variant, not success (green)" do
    get repository_path("test-repo")
    assert_response :success
    count_badge = response.body.match(
      /<span[^>]*class="([^"]*)"[^>]*>\s*(?:<svg[^>]*>.*?<\/svg>\s*)?1 tags\s*<\/span>/m
    )
    assert count_badge, "expected \"1 tags\" badge"
    badge_classes = count_badge[1]
    assert_no_match(/bg-green-|text-green-/, badge_classes, "tag count badge should not use success (green) colors")
    assert(badge_classes.include?("bg-slate-200") || badge_classes.include?("bg-slate-700"))
  end

  test "hides the native disclosure triangle so only the custom chevron shows" do
    get repository_path("test-repo")
    assert_response :success
    summary_match = response.body.match(/<summary([^>]*class="[^"]*")[^>]*>(?:.(?!<\/summary>))*?Edit description/m)
    assert summary_match, "expected summary with \"Edit description\" label"
    summary_classes = summary_match[1]
    assert_includes summary_classes, "list-none"
    assert_includes summary_classes, "[&::-webkit-details-marker]:hidden"
  end

  test "PATCH /repositories/:name persists tag_protection_policy when set to semver" do
    protection_repo = Repository.create!(name: "example", owner_identity: identities(:tonny_google))
    patch "/repositories/#{protection_repo.name}",
      params: { repository: { tag_protection_policy: "semver" } }
    assert_equal "semver", protection_repo.reload.tag_protection_policy
  end

  test "PATCH /repositories/:name persists tag_protection_pattern when policy is custom_regex" do
    protection_repo = Repository.create!(name: "example", owner_identity: identities(:tonny_google))
    patch "/repositories/#{protection_repo.name}",
      params: { repository: { tag_protection_policy: "custom_regex", tag_protection_pattern: '^release-\d+$' } }
    assert_equal "custom_regex", protection_repo.reload.tag_protection_policy
    assert_equal '^release-\d+$', protection_repo.reload.tag_protection_pattern
  end

  test "PATCH /repositories/:name clears pattern when policy reverts from custom_regex" do
    protection_repo = Repository.create!(name: "example", tag_protection_policy: "custom_regex", tag_protection_pattern: "^v.+$", owner_identity: identities(:tonny_google))
    patch "/repositories/#{protection_repo.name}",
      params: { repository: { tag_protection_policy: "semver", tag_protection_pattern: "^v.+$" } }
    assert_nil protection_repo.reload.tag_protection_pattern
  end

  test "PATCH /repositories/:name rejects invalid regex" do
    protection_repo = Repository.create!(name: "example", owner_identity: identities(:tonny_google))
    patch "/repositories/#{protection_repo.name}",
      params: { repository: { tag_protection_policy: "custom_regex", tag_protection_pattern: "[unclosed" } }
    assert_equal "none", protection_repo.reload.tag_protection_policy
  end

  test "PATCH /repositories/:name renders 422 with the validation message when regex is invalid" do
    protection_repo = Repository.create!(name: "example", owner_identity: identities(:tonny_google))
    patch "/repositories/#{protection_repo.name}",
      params: { repository: { tag_protection_policy: "custom_regex", tag_protection_pattern: "[unclosed" } }
    assert_response :unprocessable_content
    assert_match(/is not a valid regex/, response.body)
  end

  test "PATCH /repositories/:name does not crash when the invalid in-memory state touches tags in the view" do
    protection_repo = Repository.create!(name: "example", owner_identity: identities(:tonny_google))
    protection_repo.manifests.create!(
      digest: "sha256:showcrash", media_type: "application/vnd.docker.distribution.manifest.v2+json",
      payload: "{}", size: 2
    ).tap { |m| protection_repo.tags.create!(name: "v1.0.0", manifest: m) }

    patch "/repositories/#{protection_repo.name}",
      params: { repository: { tag_protection_policy: "custom_regex", tag_protection_pattern: "[unclosed" } }
    assert_response :unprocessable_content
    assert_includes response.body, "v1.0.0"
  end

  test "renders a trash heroicon in BOTH desktop and mobile Delete buttons" do
    get repository_path("test-repo")
    assert_response :success
    tag_delete_forms = response.body.scan(/<form[^>]*action="[^"]*\/tags\/[^"]*"[^>]*>.*?<\/form>/m)
    assert_equal 2, tag_delete_forms.size, "Expected 2 tag-delete forms (desktop + mobile), got #{tag_delete_forms.size}"
    forms_with_svg = tag_delete_forms.count { |form| form.include?("<svg") }
    assert_equal 2, forms_with_svg, "Expected both forms to have a trash heroicon SVG, but only #{forms_with_svg} did"
  end

  # ---------------------------------------------------------------------------
  # Stage 2: destroy authz
  # ---------------------------------------------------------------------------

  test "DELETE /repositories/:name by non-owner returns 302 redirect with alert" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "destroy-authz-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )

    # admin user (not owner) tries to delete
    post "/testing/sign_in", params: { user_id: users(:admin).id }
    delete "/repositories/#{repo.name}"

    assert_redirected_to repository_path(repo.name)
    assert_match(/permission/, flash[:alert])
    assert Repository.exists?(name: repo.name), "repository should NOT be destroyed"
  end

  test "DELETE /repositories/:name by owner succeeds" do
    owner_identity = identities(:tonny_google)
    repo = Repository.create!(
      name: "destroy-owner-#{SecureRandom.hex(4)}",
      owner_identity: owner_identity
    )

    post "/testing/sign_in", params: { user_id: users(:tonny).id }
    delete "/repositories/#{repo.name}"

    assert_redirected_to root_path
    refute Repository.exists?(name: repo.name)
  end
end
