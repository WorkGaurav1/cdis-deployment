import { test, expect } from "@playwright/test";

import { loginAs, registerTestUser, type TestUser } from "./helpers";

let user: TestUser;

test.beforeAll(async () => {
  user = await registerTestUser("auth");
});

test.describe("Login", () => {
  test("logs in through the real form and reaches the dashboard", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByRole("heading", { name: "Welcome back" })).toBeVisible();

    await page.getByLabel("Email address").fill(user.email);
    await page.getByLabel("Password", { exact: true }).fill(user.password);
    await page.getByRole("button", { name: "Sign In" }).click();

    await page.waitForURL("**/dashboard");
    await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
    // Confirms the session is real, not just a client-side route change —
    // the profile menu reads the actual authenticated user's name.
    await expect(page.getByText(user.name)).toBeVisible();
  });

  test("shows an error and stays on the login page for wrong credentials", async ({ page }) => {
    await page.goto("/login");

    await page.getByLabel("Email address").fill(user.email);
    await page.getByLabel("Password", { exact: true }).fill("the-wrong-password");
    await page.getByRole("button", { name: "Sign In" }).click();

    await expect(page.getByRole("alert")).toContainText(/invalid/i);
    await expect(page).toHaveURL(/\/login$/);
  });

  test("an authenticated session survives a full page reload", async ({ page }) => {
    await loginAs(page, user);

    await page.reload();

    await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
  });
});

test.describe("Logout", () => {
  test("logging out returns to the login page and blocks re-entry to the dashboard", async ({ page }) => {
    await loginAs(page, user);

    await page.getByRole("button", { name: "Account menu" }).click();
    await page.getByText("Log out").click();

    await page.waitForURL("**/login");

    // The session is actually gone server-side, not just hidden client-side.
    await page.goto("/dashboard");
    await page.waitForURL("**/login");
  });
});
