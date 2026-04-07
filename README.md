# F3 Region

A generic, configurable redirect site for any F3 region. Fork or deploy this repo, set three environment variables, and your region gets a branded domain that routes traffic to the right F3 Nation destinations.

## How it works

This is a Turbo monorepo with two tiny Next.js apps:

- **`apps/web`** — Redirects your domain (e.g., `f3muletown.com`) to your region page on `regions.f3nation.com`.
- **`apps/stats`** — Redirects a stats subdomain (e.g., `stats.f3muletown.com`) to your YTD stats dashboard on `pax-vault.f3nation.com`.

All redirect targets are driven by environment variables — no code changes needed.

## Setup

### 1. Configure environment variables

Copy `.env.example` to `.env` and fill in your region's values:

```bash
cp .env.example .env
```

| Variable | Example | Description |
|----------|---------|-------------|
| `REGION_SLUG` | `muletown` | Your region's slug on `regions.f3nation.com` |
| `REGION_ID` | `35838` | Your region's numeric ID (from `pax-vault.f3nation.com/stats/region/<id>`) |
| `REGION_NAME` | `Muletown` | Display name used in page titles and metadata |

### 2. Install and run

```bash
pnpm install
pnpm dev
```

- Web app: http://localhost:3000
- Stats app: http://localhost:3001

### 3. Deploy to Vercel

Deploy each app separately on Vercel, setting the environment variables in each project's settings. Point your custom domain at the web app deployment.

## Development

- `pnpm dev` — Start both apps
- `pnpm lint` — Lint all packages
- `pnpm typecheck` — Type-check all packages
- `pnpm test` — Run unit tests
- `pnpm test:e2e` — Run Playwright E2E tests
- `pnpm build` — Production build

## Project structure

```
apps/
  web/          → Region homepage redirect (port 3000)
  stats/        → Stats dashboard redirect (port 3001)
packages/
  redirects/    → Shared redirect logic (reads env vars)
  eslint-config/
  prettier-config/
  tsconfig/
  vitest-config/
```
