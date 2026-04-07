const REGION_BASE_URL = "https://regions.f3nation.com";
const STATS_BASE_URL = "https://pax-vault.f3nation.com/stats/region";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing required environment variable: ${name}. See .env.example for details.`
    );
  }
  return value;
}

export function getRegionSlug(): string {
  return requireEnv("REGION_SLUG");
}

export function getRegionId(): string {
  return requireEnv("REGION_ID");
}

export function getRegionName(): string {
  return requireEnv("REGION_NAME");
}

export function getRegionRedirectUrl(slug?: string): string {
  return `${REGION_BASE_URL}/${slug ?? getRegionSlug()}`;
}

export function getStatsRedirectUrl(): string {
  return `${STATS_BASE_URL}/${getRegionId()}`;
}

export const redirects = {
  regionHome: getRegionRedirectUrl,
  stats: getStatsRedirectUrl,
} as const;
