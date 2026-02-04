const { test, expect } = require('@playwright/test');

test.describe('Tag Details', () => {
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
    await expect(page.locator('th:has-text("Tag")')).toBeVisible();
    await expect(page.locator('th:has-text("Digest")')).toBeVisible();
    await expect(page.locator('th:has-text("Size")')).toBeVisible();
    await expect(page.locator('th:has-text("Created")')).toBeVisible();
  });

  test('should display tag rows', async ({ page }) => {
    const tagRows = page.locator('tbody tr');
    const count = await tagRows.count();
    expect(count).toBeGreaterThan(0);
  });

  test('should display copy button for each tag', async ({ page }) => {
    const copyButtons = page.locator('button:has-text("Copy")');
    const count = await copyButtons.count();
    expect(count).toBeGreaterThan(0);
  });

  test('should navigate back to repository list', async ({ page }) => {
    await page.click('text=Back to Repositories');
    await expect(page).toHaveURL(/\/(repositories)?$/);
    await expect(page.locator('h1')).toContainText('Docker Registry');
  });
});
