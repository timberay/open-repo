const { test, expect } = require('@playwright/test');

test.describe('Registry Switching', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/registries');

    const hasRegistries = await page.locator('table').isVisible().catch(() => false);

    if (!hasRegistries) {
      await page.click('text=Add Registry');
      await page.fill('input[name="registry[name]"]', 'Test Registry');
      await page.fill('input[name="registry[url]"]', 'http://localhost:5000');
      await page.click('input[type="submit"]');
      await page.waitForURL('/registries');
    }
  });

  test('should display registry in dropdown after creation', async ({ page }) => {
    await page.goto('/');

    const dropdownButton = page.locator('[data-action*="registry-selector#toggle"]');
    await dropdownButton.click();

    const registryItems = page.locator('[data-registry-id]');
    const count = await registryItems.count();
    expect(count).toBeGreaterThan(0);
  });

  test('should show connection status icons', async ({ page }) => {
    await page.goto('/');

    const dropdownButton = page.locator('[data-action*="registry-selector#toggle"]');
    await dropdownButton.click();

    const statusIcons = page.locator('text=/[●○◐]/');
    const count = await statusIcons.count();
    expect(count).toBeGreaterThan(0);
  });
});
