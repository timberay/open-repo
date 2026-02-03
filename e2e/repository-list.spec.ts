import { test, expect } from '@playwright/test';

test.describe('Repository List', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should display repository list page', async ({ page }) => {
    await expect(page.locator('h1')).toContainText('Docker Registry');
    await expect(page.locator('text=Browse and search Docker images')).toBeVisible();
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
    await page.fill('input[placeholder="Search repositories..."]', 'nonexistentrepo12345');
    await page.waitForTimeout(500);
    
    await expect(page.locator('text=No repositories found')).toBeVisible();
  });
});
