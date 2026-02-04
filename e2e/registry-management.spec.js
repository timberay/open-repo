const { test, expect } = require('@playwright/test');

test.describe('Registry Management', () => {
  test('should navigate to registry management page', async ({ page }) => {
    await page.goto('/registries');
    await expect(page.locator('h1')).toContainText('Registry Management');
  });

  test('should display Add Registry button', async ({ page }) => {
    await page.goto('/registries');
    const addButton = page.locator('text=Add Registry').first();
    await expect(addButton).toBeVisible();
  });

  test('should navigate to new registry form', async ({ page }) => {
    await page.goto('/registries');
    await page.click('text=Add Registry');
    
    await expect(page).toHaveURL('/registries/new');
    await expect(page.locator('h1')).toContainText('Add New Registry');
  });

  test('should display registry form fields', async ({ page }) => {
    await page.goto('/registries/new');
    
    await expect(page.locator('input[name="registry[name]"]')).toBeVisible();
    await expect(page.locator('input[name="registry[url]"]')).toBeVisible();
    await expect(page.locator('input[name="registry[username]"]')).toBeVisible();
    await expect(page.locator('input[name="registry[password]"]')).toBeVisible();
  });

  test('should show Test Connection button', async ({ page }) => {
    await page.goto('/registries/new');
    const testButton = page.locator('button:has-text("Test Connection")');
    await expect(testButton).toBeVisible();
  });

  test('should validate required fields', async ({ page }) => {
    await page.goto('/registries/new');
    
    const nameInput = page.locator('input[name="registry[name]"]');
    const urlInput = page.locator('input[name="registry[url]"]');
    
    const nameRequired = await nameInput.getAttribute('required');
    const urlRequired = await urlInput.getAttribute('required');
    
    expect(nameRequired).not.toBeNull();
    expect(urlRequired).not.toBeNull();
  });
});
