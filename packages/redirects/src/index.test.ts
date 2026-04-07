import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  getRegionRedirectUrl,
  getRegionSlug,
  getStatsRedirectUrl,
  redirects,
} from "./index";

describe("@f3-region/redirects", () => {
  beforeEach(() => {
    vi.stubEnv("REGION_SLUG", "muletown");
    vi.stubEnv("REGION_ID", "35838");
    vi.stubEnv("REGION_NAME", "Muletown");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  describe("getRegionSlug", () => {
    it("returns the REGION_SLUG env var", () => {
      expect(getRegionSlug()).toBe("muletown");
    });

    it("throws when REGION_SLUG is not set", () => {
      vi.stubEnv("REGION_SLUG", "");

      expect(() => getRegionSlug()).toThrow(
        "Missing required environment variable: REGION_SLUG"
      );
    });
  });

  describe("getRegionRedirectUrl", () => {
    it("returns the region redirect using REGION_SLUG", () => {
      expect(getRegionRedirectUrl()).toBe(
        "https://regions.f3nation.com/muletown"
      );
    });

    it("allows overriding the region slug", () => {
      expect(getRegionRedirectUrl("nashville")).toBe(
        "https://regions.f3nation.com/nashville"
      );
    });
  });

  describe("getStatsRedirectUrl", () => {
    it("returns the stats redirect using REGION_ID", () => {
      expect(getStatsRedirectUrl()).toBe(
        "https://pax-vault.f3nation.com/stats/region/35838"
      );
    });

    it("throws when REGION_ID is not set", () => {
      vi.stubEnv("REGION_ID", "");

      expect(() => getStatsRedirectUrl()).toThrow(
        "Missing required environment variable: REGION_ID"
      );
    });
  });

  describe("redirects helper", () => {
    it("provides a region home shortcut", () => {
      expect(redirects.regionHome()).toBe(
        "https://regions.f3nation.com/muletown"
      );

      expect(redirects.regionHome("nashville")).toBe(
        "https://regions.f3nation.com/nashville"
      );
    });

    it("provides a stats shortcut", () => {
      expect(redirects.stats()).toBe(
        "https://pax-vault.f3nation.com/stats/region/35838"
      );
    });
  });
});
