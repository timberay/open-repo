const { test, expect } = require('@playwright/test');
const { execSync } = require('child_process');

const repoName = 'e2e-tag-protection-repo';
const protectedTag = 'v1.0.0';
const floatingTag = 'latest';

test.describe('Tag Protection', () => {
  test.beforeAll(() => {
    execSync(`bin/rails runner '
      repo = Repository.find_or_create_by!(name: "${repoName}")
      m = repo.manifests.find_or_create_by!(digest: "sha256:e2e-seed") do |x|
        x.media_type = "application/vnd.docker.distribution.manifest.v2+json"
        x.payload = "{}"
        x.size = 2
      end
      repo.tags.find_or_create_by!(name: "${protectedTag}") { |t| t.manifest = m }
      repo.tags.find_or_create_by!(name: "${floatingTag}") { |t| t.manifest = m }
      repo.update!(tag_protection_policy: "semver")
    '`, { stdio: 'inherit' });
  });

  test.afterAll(() => {
    execSync(`bin/rails runner 'Repository.find_by(name: "${repoName}")&.destroy!'`, { stdio: 'inherit' });
  });

  test('policy save reflects 🔒 badge and disabled delete button', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`);

    const protectedRow = page.locator(`a:has-text("${protectedTag}")`).locator('..');
    await expect(protectedRow.getByText('🔒 Protected')).toBeVisible();

    const floatingRow = page.locator(`a:has-text("${floatingTag}")`).locator('..');
    await expect(floatingRow.getByText('🔒 Protected')).toHaveCount(0);
  });

  test('protected tag delete button on repo show is disabled with tooltip', async ({ page }) => {
    await page.goto(`/repositories/${repoName}`);
    const protectedRow = page.locator(`a:has-text("${protectedTag}")`).locator('../..');
    const disabledDelete = protectedRow.getByText('Delete', { exact: false }).first();
    await expect(disabledDelete).toHaveAttribute('title', /Change the repository's tag protection policy/);
  });

  test('protected tag detail page shows disabled delete button', async ({ page }) => {
    await page.goto(`/repositories/${repoName}/tags/${protectedTag}`);
    const btn = page.getByText('Delete tag (protected)');
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
