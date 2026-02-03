import { test, expect } from '@playwright/test';

test.describe('Registry Dropdown', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should display registry selector in navbar', async ({ page }) => {
    const selector = page.locator('[data-controller="registry-selector"]');
    await expect(selector).toBeVisible();
  });

  test('should toggle dropdown on click', async ({ page }) => {
    const button = page.locator('[data-action*="registry-selector#toggle"]');
    const dropdown = page.locator('[data-registry-selector-target="dropdown"]');
    
    await button.click();
    await expect(dropdown).toBeVisible();
    
    await button.click();
    await expect(dropdown).toBeHidden();
  });

  test('should close dropdown when clicking outside', async ({ page }) => {
    const button = page.locator('[data-action*="registry-selector#toggle"]');
    const dropdown = page.locator('[data-registry-selector-target="dropdown"]');
    
    await button.click();
    await expect(dropdown).toBeVisible();
    
    await page.click('body');
    await page.waitForTimeout(100);
    await expect(dropdown).toBeHidden();
  });

  test('should display Manage Registries link', async ({ page }) => {
    const button = page.locator('[data-action*="registry-selector#toggle"]');
    await button.click();
    
    const manageLink = page.locator('text=Manage Registries');
    await expect(manageLink).toBeVisible();
  });
});
