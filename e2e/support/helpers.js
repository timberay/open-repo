// Shared helpers for Playwright specs.
//
// - `seedBaseline()` runs the Ruby seed script via `bin/rails runner`.
//   It returns `{ user_id, owner_identity_id }`.
// - `signIn(page, userId)` signs the browser session in as the given user
//   by POSTing to `/testing/sign_in` (mounted in development when
//   USE_MOCK_REGISTRY=true — see config/routes.rb).
// - `runRailsRunner(code)` is an escape hatch for per-spec fixtures that need
//   to create additional rows on top of the baseline (e.g. tag-protection).

const { execSync } = require('child_process');

function runRailsRunner(script) {
  const output = execSync('bin/rails runner -', {
    input: script,
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  return output.toString();
}

function seedBaseline() {
  const raw = execSync('bin/rails runner e2e/support/seed.rb').toString().trim();
  // Seed script prints one JSON line at the end; grab it.
  const lastLine = raw.split('\n').filter(Boolean).pop();
  return JSON.parse(lastLine);
}

async function signIn(page, userId) {
  // Use the request context so cookies are set on the browser context
  // before we navigate. baseURL from playwright.config.js is applied.
  const response = await page.request.post('/testing/sign_in', {
    form: { user_id: String(userId) },
  });
  if (!response.ok()) {
    throw new Error(`signIn failed: ${response.status()} ${await response.text()}`);
  }
}

module.exports = { seedBaseline, signIn, runRailsRunner };
