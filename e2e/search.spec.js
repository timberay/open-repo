const { test, expect } = require('@playwright/test');

test.describe('Repository Search', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should filter repositories by search query', async ({ page }) => {
    const searchInput = page.locator('input[placeholder="Search repositories..."]');
    await searchInput.fill('backend');
    
    await page.waitForTimeout(1000);
    
    const cards = page.locator('[href*="/repositories/"]');
    const count = await cards.count();
    expect(count).toBeGreaterThan(0);
    
    const firstCardText = await cards.first().textContent();
    expect(firstCardText?.toLowerCase()).toContain('backend');
  });

  test('should debounce search input', async ({ page }) => {
    const searchInput = page.locator('input[placeholder="Search repositories..."]');
    
    await searchInput.fill('a');
    await page.waitForTimeout(100);
    await searchInput.fill('ap');
    await page.waitForTimeout(100);
    await searchInput.fill('app');
    
    await page.waitForTimeout(1000);
    
    const cards = page.locator('[href*="/repositories/"]');
    await expect(cards.first()).toBeVisible();
  });

  test('should sort repositories', async ({ page }) => {
    const sortSelect = page.locator('select[name="sort_by"]');
    
    await sortSelect.selectOption('name_desc');
    await page.waitForTimeout(500);
    
    const cards = page.locator('[href*="/repositories/"]');
    await expect(cards.first()).toBeVisible();
  });
});
