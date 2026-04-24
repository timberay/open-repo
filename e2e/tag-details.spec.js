const { test, expect } = require('@playwright/test');
const { seedBaseline } = require('./support/helpers');

// This spec exercises the tags list rendered on the repository show page
// (the "Tag Details" name is historical — the page is /repositories/:name,
// not the per-tag detail page). It relies on data-testid anchors added to
// `app/views/repositories/show.html.erb` so selectors stay stable across
// visual refactors.

test.describe('Tag Details', () => {
  test.beforeAll(() => {
    seedBaseline();
  });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    const firstRepo = page.locator('[href*="/repositories/"]').first();
    await firstRepo.click();
    await page.waitForLoadState('networkidle');
  });

  test('should display repository details page', async ({ page }) => {
    await expect(page.locator('text=Back to Repositories')).toBeVisible();
    await expect(page.locator('span:has-text("tags")')).toBeVisible();
  });

  test('should display tags table', async ({ page }) => {
    const table = page.locator('[data-testid="tags-table"]');
    await expect(table).toBeVisible();
    await expect(table.locator('[data-testid="tags-header-cell"][data-col="tag"]')).toBeVisible();
    await expect(table.locator('[data-testid="tags-header-cell"][data-col="digest"]')).toBeVisible();
    await expect(table.locator('[data-testid="tags-header-cell"][data-col="size"]')).toBeVisible();
    await expect(table.locator('[data-testid="tags-header-cell"][data-col="updated"]')).toBeVisible();
  });

  test('should display tag rows', async ({ page }) => {
    const tagRows = page.locator('[data-testid="tag-row"]');
    const count = await tagRows.count();
    expect(count).toBeGreaterThan(0);
  });

  test('should display a copy button for the pull command', async ({ page }) => {
    const copyButtons = page.locator('[data-testid="copy-pull-command"]');
    await expect(copyButtons.first()).toBeVisible();
  });

  test('should navigate back to repository list', async ({ page }) => {
    await page.click('text=Back to Repositories');
    await expect(page).toHaveURL(/\/(repositories)?$/);
    await expect(page.locator('h1')).toContainText('Repositories');
  });
});
