const { test, expect } = require('@playwright/test');

test('verify layout and dark mode', async ({ page }) => {
  page.on('console', msg => console.log('PAGE LOG:', msg.text()));
  page.on('pageerror', exception => console.log(`PAGE ERROR: "${exception}"`));
  page.on('requestfailed', request => {
    console.log(request.url() + ' ' + request.failure().errorText);
  });

  // 1. Go to home page
  await page.goto('http://localhost:3000', { waitUntil: 'networkidle' });
  
  // Debug: check stylesheets
  const styleCount = await page.evaluate(() => document.styleSheets.length);
  console.log(`Stylesheets loaded: ${styleCount}`);
  
  await page.screenshot({ path: '.sisyphus/evidence/debug_layout.png' });

  // 2. Check html data-controller
  const html = page.locator('html');
  await expect(html).toHaveAttribute('data-controller', 'theme');

  // 3. Check Navigation Bar
  const nav = page.locator('nav');
  await expect(nav).toBeVisible();
  await expect(page.locator('text=RepoVista')).toBeVisible();

  // 4. Check Dark Mode Toggle
  const toggleBtn = page.locator('button[data-action="click->theme#toggle"]');
  await expect(toggleBtn).toBeVisible();

  // 5. Test Toggle functionality
  // Initially might be light or dark depending on system, but let's check toggle behavior
  const classAttr = await html.getAttribute('class');
  const isDarkInitially = classAttr ? classAttr.includes('dark') : false;
  
  await toggleBtn.click();
  
  if (isDarkInitially) {
    await expect(html).not.toHaveClass(/dark/);
  } else {
    await expect(html).toHaveClass(/dark/);
  }

  // Toggle back
  await toggleBtn.click();
  
  if (isDarkInitially) {
    await expect(html).toHaveClass(/dark/);
  } else {
    await expect(html).not.toHaveClass(/dark/);
  }

  // 6. Screenshot
  await page.screenshot({ path: '.sisyphus/evidence/task-4-layout.png', fullPage: true });
});
