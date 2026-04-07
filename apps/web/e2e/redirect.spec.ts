import { expect, test } from "@playwright/test";

const regionSlug = process.env.REGION_SLUG ?? "muletown";
const regionId = process.env.REGION_ID ?? "35838";

const targetHost = "regions.f3nation.com";
const targetPath = `/${regionSlug}`;

const statsHost = "pax-vault.f3nation.com";
const statsPath = `/stats/region/${regionId}`;

test("redirects homepage to the regions site", async ({ page }) => {
  // Some third-party assets on the target site never finish loading; wait for the navigation to commit only.
  await page.goto("/", { waitUntil: "commit" });

  await page.waitForURL(
    (url) => url.host === targetHost && url.pathname.startsWith(targetPath),
    { timeout: 15_000 }
  );

  const url = new URL(page.url());

  expect(url.protocol).toBe("https:");
  expect(url.host).toBe(targetHost);
  expect(url.pathname).toMatch(new RegExp(`^/${regionSlug}/?$`));
});

test("redirects /stats to the stats page", async ({ page }) => {
  await page.goto("/stats", { waitUntil: "commit" });

  await page.waitForURL(
    (url) => url.host === statsHost && url.pathname === statsPath,
    { timeout: 15_000 }
  );

  const url = new URL(page.url());

  expect(url.protocol).toBe("https:");
  expect(url.host).toBe(statsHost);
  expect(url.pathname).toBe(statsPath);
});
