import { expect, type Page, test } from "@playwright/test"

/**
 * The UI half of the permission matrix: nav entries are hidden, and a direct
 * URL to a forbidden route shows Access denied rather than redirecting away.
 *
 * Requires the seeded demo accounts: `python -m app.seed_data`.
 */

test.use({ storageState: { cookies: [], origins: [] } })

const DEMO_PASSWORD = "changethis"

async function signIn(page: Page, email: string) {
  await page.goto("/login")
  await page.getByTestId("email-input").fill(email)
  await page.getByTestId("password-input").fill(DEMO_PASSWORD)
  await page.getByRole("button", { name: "Log In" }).click()
  await page.waitForURL("/")
}

test("member sees no privileged nav and is told why on /admin", async ({ page }) => {
  await signIn(page, "member@example.com")

  await expect(page.getByRole("link", { name: "Dashboard" })).toBeVisible()
  await expect(page.getByRole("link", { name: "Admin" })).toHaveCount(0)
  await expect(page.getByRole("link", { name: "Metrics" })).toHaveCount(0)

  await page.goto("/admin")
  await expect(page.getByTestId("forbidden")).toBeVisible()
  await expect(page).toHaveURL(/\/admin$/) // an explicit refusal, not a redirect
})

test("manager lists users and views metrics but cannot create users", async ({ page }) => {
  await signIn(page, "manager@example.com")
  await expect(page.getByRole("link", { name: "Admin" })).toBeVisible()

  await page.goto("/admin")
  // Assert the table rendered first — otherwise "no Add User" would also pass
  // on a page that failed to load at all.
  await expect(page.getByText("manager@example.com")).toBeVisible()
  await expect(page.getByRole("button", { name: "Add User" })).toHaveCount(0)

  await page.goto("/metrics")
  await expect(page.getByText("Total users")).toBeVisible()
})

test("admin can reach every gated surface", async ({ page }) => {
  await signIn(page, "admin@example.com")

  await page.goto("/admin")
  await expect(page.getByText("manager@example.com")).toBeVisible()
  await expect(page.getByRole("button", { name: "Add User" })).toBeVisible()

  await page.goto("/metrics")
  await expect(page.getByText("Total users")).toBeVisible()
})
