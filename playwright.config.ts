import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end suite: drives the real integrated system — reverse proxy
 * -> frontend/backend containers -> real MySQL — not sibling dev
 * processes on this machine. Deliberately does NOT use Playwright's
 * `webServer` option: bringing up a multi-container stack (build,
 * healthy-wait, migrate, seed) is more than that feature is meant to
 * orchestrate, so it's a separate, reusable step instead.
 *
 * Bring the environment up first:
 *   ./scripts/e2e-up.sh          (local: builds from sibling repo checkouts)
 * then run against it:
 *   npx playwright test
 * or point at any other already-running environment (a staging/prod
 * URL) via E2E_BASE_URL, without needing this repo's own compose stack
 * running at all:
 *   E2E_BASE_URL=https://cdis.example.com npx playwright test
 */
const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:8080";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  timeout: 30_000,

  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
