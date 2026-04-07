# F3 Region

A generic, configurable redirect site for any F3 region. Each region can deploy the same codebase, inject three region-specific environment variables, and publish its own branded domains without changing application code.

## What this repo does

This is a Turbo monorepo with two small Next.js apps:

- `apps/web` redirects the main region domain, such as `f3muletown.com`, to `regions.f3nation.com/<region-slug>`.
- `apps/stats` redirects a stats subdomain, such as `stats.f3muletown.com`, to `pax-vault.f3nation.com/stats/region/<region-id>`.

Both apps use the same runtime env contract:

- `REGION_SLUG`
- `REGION_ID`
- `REGION_NAME`

Those values match the generic redirect behavior in this repo and cover the same region-specific data the Muletown setup needs.

## Preferred deployment path: minimal Cloud Run with Terraform

This repo now includes a Terraform stack at [infra/terraform/cloud-run/README.md](/Users/patrick/workspaces/clients/f3-nation/f3-redirect/infra/terraform/cloud-run/README.md) that provisions:

- Artifact Registry for Docker images
- one Cloud Run service for `apps/web`
- one Cloud Run service for `apps/stats`
- runtime service accounts
- public access for both services by default
- optional direct Cloud Run custom-domain mappings for each service

### High-level flow

1. Copy [infra/terraform/cloud-run/terraform.tfvars.example](/Users/patrick/workspaces/clients/f3-nation/f3-redirect/infra/terraform/cloud-run/terraform.tfvars.example) to `terraform.tfvars`.
2. Fill in your Google Cloud project, Cloud Run region, image tags, and the three region env vars.
3. Run a targeted Terraform apply to create Artifact Registry first.
4. Build and push `Dockerfile.web` and `Dockerfile.stats`.
5. Run `terraform apply` for the full stack so the two Cloud Run services point at those pushed images.
6. If you set `web_domain` and `stats_domain`, copy the Terraform output DNS records into GoDaddy.

This path is intentionally cheap and simple. It uses Cloud Run domain mappings directly instead of adding an HTTPS load balancer.

## Local development

Copy [.env.example](/Users/patrick/workspaces/clients/f3-nation/f3-redirect/.env.example) to `.env` and fill in your region's values:

```bash
cp .env.example .env
pnpm install
pnpm dev
```

Local ports:

- web app: `http://localhost:3000`
- stats app: `http://localhost:3001`

## Environment variables

| Variable | Example | Description |
|----------|---------|-------------|
| `REGION_SLUG` | `muletown` | Region slug on `regions.f3nation.com` |
| `REGION_ID` | `35838` | Numeric ID from `pax-vault.f3nation.com/stats/region/<id>` |
| `REGION_NAME` | `Muletown` | Display name used in page titles and metadata |

## Development commands

- `pnpm dev` starts both apps
- `pnpm lint` lints all packages
- `pnpm typecheck` runs TypeScript checks
- `pnpm test` runs unit tests
- `pnpm test:e2e` runs Playwright end-to-end tests
- `pnpm build` creates production builds

## Container files

- [Dockerfile.web](/Users/patrick/workspaces/clients/f3-nation/f3-redirect/Dockerfile.web) builds the main region redirect app for Cloud Run.
- [Dockerfile.stats](/Users/patrick/workspaces/clients/f3-nation/f3-redirect/Dockerfile.stats) builds the stats redirect app for Cloud Run.

Both use Next.js standalone output so Cloud Run only needs the production runtime artifacts.
