const { test, expect } = require('@playwright/test');
const { seedBaseline } = require('./support/helpers');

const SEARCH_SELECTOR = 'input[placeholder="Search by name, description, or maintainer..."]';

test.describe('Repository Search', () => {
  test.beforeAll(() => {
    seedBaseline();
  });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should filter repositories by search query', async ({ page }) => {
    const searchInput = page.locator(SEARCH_SELECTOR);
    await searchInput.fill('backend');

    await page.waitForTimeout(1000);

    const cards = page.locator('[href*="/repositories/"]');
    const count = await cards.count();
    expect(count).toBeGreaterThan(0);

    const firstCardText = await cards.first().textContent();
    expect(firstCardText?.toLowerCase()).toContain('backend');
  });

  test('should debounce search input', async ({ page }) => {
    const searchInput = page.locator(SEARCH_SELECTOR);

    await searchInput.fill('b');
    await page.waitForTimeout(100);
    await searchInput.fill('ba');
    await page.waitForTimeout(100);
    await searchInput.fill('backend');

    await page.waitForTimeout(1000);

    const cards = page.locator('[href*="/repositories/"]');
    await expect(cards.first()).toBeVisible();
  });

  test('should sort repositories', async ({ page }) => {
    // The sort control is a <select name="sort"> with options
    // ["", "name", "size", "pulls"]. "name" sorts alphabetically
    // ascending (A-Z); the UI no longer exposes a descending option.
    const sortSelect = page.locator('select[name="sort"]');

    await sortSelect.selectOption('name');
    await page.waitForTimeout(500);

    const cards = page.locator('[href*="/repositories/"]');
    await expect(cards.first()).toBeVisible();

    // Verify sort applied: with seed data (backend-api, frontend-web,
    // worker-jobs), backend-api must render first under name ASC.
    const firstHref = await cards.first().getAttribute('href');
    expect(firstHref).toContain('backend-api');
  });
});
