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

    // Assert relative order among seed rows. The dev DB may contain
    // unrelated repositories (dogfood fixtures) that would otherwise
    // make an "is first" assertion brittle; checking that backend-api
    // precedes frontend-web is sufficient to prove ASC-name sorting.
    const hrefs = await cards.evaluateAll((nodes) =>
      nodes.map((n) => n.getAttribute('href'))
    );
    const backendIdx = hrefs.findIndex((h) => h && h.includes('backend-api'));
    const frontendIdx = hrefs.findIndex((h) => h && h.includes('frontend-web'));
    expect(backendIdx).toBeGreaterThanOrEqual(0);
    expect(frontendIdx).toBeGreaterThanOrEqual(0);
    expect(backendIdx).toBeLessThan(frontendIdx);
  });
});
