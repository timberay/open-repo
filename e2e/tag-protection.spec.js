const { test, expect } = require('@playwright/test');
const { seedBaseline, runRailsRunner, signIn } = require('./support/helpers');

const repoName = 'e2e-tag-protection-repo';
const protectedTag = 'v1.0.0';
const floatingTag = 'latest';

test.describe('Tag Protection', () => {
  test.describe.configure({ mode: 'serial' });

  let ownerUserId;

  test.beforeAll(() => {
    // Baseline seed creates owner_user + owner_identity, which the repo
    // below reuses. Without this, Repository.create! fails validation:
    // "Owner identity must exist".
    const baseline = seedBaseline();
    ownerUserId = baseline.user_id;

    runRailsRunner(`
      owner_identity = Identity.find(${baseline.owner_identity_id})
      repo = Repository.find_or_create_by!(name: "${repoName}") do |r|
        r.owner_identity = owner_identity
      end
      repo.update!(owner_identity: owner_identity)
      m = repo.manifests.find_or_create_by!(digest: "sha256:e2e-${repoName}") do |x|
        x.media_type = "application/vnd.docker.distribution.manifest.v2+json"
        x.payload = "{}"
        x.size = 2
      end
      repo.tags.find_or_create_by!(name: "${protectedTag}") { |t| t.manifest = m }
      repo.tags.find_or_create_by!(name: "${floatingTag}") { |t| t.manifest = m }
      repo.update!(tag_protection_policy: "semver")
    `);
  });

  test.afterAll(() => {
    runRailsRunner(`Repository.find_by(name: "${repoName}")&.destroy!`);
  });

  test.beforeEach(async ({ page }) => {
    // Sign in as the repository owner so PATCH /repositories/:name
    // (edit form submit) passes authorize_for!(:write).
    await signIn(page, ownerUserId);
  });

  test('policy save reflects protected badge on matching tags only', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`);

    const protectedRow = page.locator(`[data-testid="tag-row"][data-tag-name="${protectedTag}"]`);
    await expect(protectedRow.locator('[data-testid="tag-protected-badge"]')).toBeVisible();

    const floatingRow = page.locator(`[data-testid="tag-row"][data-tag-name="${floatingTag}"]`);
    await expect(floatingRow.locator('[data-testid="tag-protected-badge"]')).toHaveCount(0);
  });

  test('protected tag delete button on repo show is disabled with tooltip', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`);
    const protectedRow = page.locator(`[data-testid="tag-row"][data-tag-name="${protectedTag}"]`);
    const disabled = protectedRow.locator('[data-testid="tag-delete-disabled"]');
    await expect(disabled).toBeVisible();
    await expect(disabled).toHaveAttribute('title', /Change the repository's tag protection policy/);
  });

  test('protected tag detail page shows disabled delete button', async ({ page }) => {
    await page.goto(`/repositories/${repoName}/tags/${protectedTag}`);
    const btn = page.locator('[data-testid="tag-delete-protected"]');
    await expect(btn).toBeVisible();
    await expect(btn).toHaveAttribute('title', /Change the repository's tag protection policy/);
  });

  test('custom_regex shows regex input, non-custom hides it', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`);
    await page.getByText('Edit description & maintainer').click();

    const regexInput = page.locator('input[name="repository[tag_protection_pattern]"]');

    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'custom_regex');
    await expect(regexInput).toBeVisible();

    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'semver');
    await expect(regexInput).not.toBeVisible();
  });

  test('invalid regex surfaces validation error', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`);
    await page.getByText('Edit description & maintainer').click();
    await page.selectOption('select[name="repository[tag_protection_policy]"]', 'custom_regex');
    await page.fill('input[name="repository[tag_protection_pattern]"]', '[unclosed');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText(/is not a valid regex/)).toBeVisible();
  });
});
