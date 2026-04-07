import { redirect } from "next/navigation";
import { afterEach, describe, expect, it, vi } from "vitest";

import { getStatsRedirectUrl } from "@f3-region/redirects";

import Home from "./page";

vi.mock("next/navigation", () => ({
  redirect: vi.fn(),
}));

vi.mock("@f3-region/redirects", () => ({
  getStatsRedirectUrl: vi.fn(
    () => "https://pax-vault.f3nation.com/stats/region/12345"
  ),
}));

const mockedRedirect = vi.mocked(redirect);

describe("stats redirect", () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it("redirects to the stats page", () => {
    Home();

    expect(mockedRedirect).toHaveBeenCalledWith(getStatsRedirectUrl());
  });
});
