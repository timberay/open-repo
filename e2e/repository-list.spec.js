const { test, expect } = require('@playwright/test');
const { seedBaseline } = require('./support/helpers');

test.describe('Repository List', () => {
  test.beforeAll(() => {
    seedBaseline();
  });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should display repository list page', async ({ page }) => {
    await expect(page.locator('h1')).toContainText('Repositories');
    // The app no longer renders a "Browse and search Docker images"
    // subtitle — the header is intentionally minimal (only the H1).
    // Assert instead on the search control that is the defining
    // interactive element of the page header.
    await expect(
      page.locator('input[placeholder="Search by name, description, or maintainer..."]')
    ).toBeVisible();
  });

  test('should display repository cards', async ({ page }) => {
    const cards = page.locator('[href*="/repositories/"]');
    await expect(cards.first()).toBeVisible();
  });

  test('should navigate to repository details', async ({ page }) => {
    const firstRepo = page.locator('[href*="/repositories/"]').first();
    await firstRepo.click();

    await expect(page).toHaveURL(/\/repositories\/.+/);
    await expect(page.locator('text=Back to Repositories')).toBeVisible();
  });

  test('should display no results message when search returns empty', async ({ page }) => {
    await page.fill(
      'input[placeholder="Search by name, description, or maintainer..."]',
      'nonexistentrepo12345'
    );
    await page.waitForTimeout(500);

    await expect(page.locator('text=No results found')).toBeVisible();
  });
});
