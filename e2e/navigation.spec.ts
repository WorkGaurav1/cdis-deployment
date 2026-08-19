import { test, expect } from "@playwright/test";

import { loginAs, registerTestUser, type TestUser } from "./helpers";

let user: TestUser;

test.beforeAll(async () => {
  user = await registerTestUser("nav");
});

test.beforeEach(async ({ page }) => {
  await loginAs(page, user);
});

test.describe("Sidebar navigation", () => {
  test("Graphs page loads via the sidebar link", async ({ page }) => {
    await page.getByRole("link", { name: "Graphs" }).first().click();
    await expect(page).toHaveURL(/\/graphs$/);
    await expect(page.getByRole("heading", { name: "Graphs" })).toBeVisible();
  });

  test("Charts page loads via the sidebar link", async ({ page }) => {
    await page.getByRole("link", { name: "Charts" }).first().click();
    await expect(page).toHaveURL(/\/charts$/);
    await expect(page.getByRole("heading", { name: "Charts" })).toBeVisible();
  });

  test("Table page loads via the sidebar link", async ({ page }) => {
    await page.getByRole("link", { name: "Table" }).first().click();
    await expect(page).toHaveURL(/\/tables$/);
    await expect(page.getByRole("heading", { name: "Table" })).toBeVisible();
  });
});

test.describe("Account menu navigation", () => {
  test("Settings page loads via the account menu and shows the real session's details", async ({ page }) => {
    await page.getByRole("button", { name: "Account menu" }).click();
    await page.getByText("Settings").click();

    await expect(page).toHaveURL(/\/settings$/);
    await expect(page.getByRole("heading", { name: "Settings" })).toBeVisible();
    await expect(page.getByText(user.email)).toBeVisible();
  });
});

test.describe("Permission-gated routes", () => {
  test("a plain (non-manager) user is redirected to /forbidden when visiting /users directly", async ({ page }) => {
    await page.goto("/users");

    await page.waitForURL("**/forbidden");
    await expect(page.getByRole("heading", { name: "403 - Access Denied" })).toBeVisible();
    // The permission gate also hides the link itself, not just the route.
    await expect(page.getByRole("link", { name: "Users" })).not.toBeVisible();
  });
});

test.describe("Catch-all", () => {
  test("an unknown path renders the 404 page", async ({ page }) => {
    await page.goto("/this-route-does-not-exist");

    await expect(page.getByRole("heading", { name: "404 - Page Not Found" })).toBeVisible();
  });
});
