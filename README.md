# F3 Redirect

A branded redirect site for any F3 region. Your region gets its own domain (like `f3muletown.com`) that automatically sends visitors to the right places on F3 Nation — no website to maintain.

## What does this do?

When someone visits your region's domain, they're instantly redirected:

| Visitor goes to...     | They land on...                                                     |
| ---------------------- | ------------------------------------------------------------------- |
| `f3muletown.com`       | Your region page on `regions.f3nation.com/muletown`                 |
| `stats.f3muletown.com` | Your stats dashboard on `pax-vault.f3nation.com/stats/region/35838` |

That's it. No content to manage, no website to maintain. Just two clean redirects.

## Getting started

### What you'll need

1. **A domain name** — buy one from GoDaddy, Namecheap, etc. (e.g., `f3muletown.com`, ~$12/year)
2. **A Google Cloud account** — free to create, and Cloud Run has a generous free tier
3. **Claude Code** — the CLI tool that walks you through deployment step by step

### What it costs

- **Domain**: ~$12/year
- **Google Cloud Run**: likely **free** for redirect traffic. Cloud Run's free tier includes 2 million requests/month. A regional redirect site will use a tiny fraction of that.
- **Total**: ~$1/month or less

### Deploy with Claude Code

Open this repo in Claude Code and run the deployment skill:

```
/f3-region-gcp-terraform-deploy muletown
```

Claude will walk you through every step:

1. **Ask for your region's details** — slug, ID, display name, and domains
2. **Set up Google Cloud** — create a project, enable the right services
3. **Build and deploy** — package the apps and push them to Cloud Run
4. **Give you DNS records** — exact records to add in GoDaddy (or your DNS provider)

After adding the DNS records, your domain goes live within a few minutes.

### Three values that make it yours

Every region is configured with just three values:

| Value           | Where to find it                                         | Example    |
| --------------- | -------------------------------------------------------- | ---------- |
| **Region slug** | The end of your URL on `regions.f3nation.com/<slug>`     | `muletown` |
| **Region ID**   | The number in `pax-vault.f3nation.com/stats/region/<id>` | `35838`    |
| **Region name** | What you call your region                                | `Muletown` |

The deployment skill will ask you for these.

## For developers

### Architecture

This is a Turbo monorepo with two Next.js apps that each do one thing — redirect and exit:

- **`apps/web`** — redirects the apex domain to `regions.f3nation.com/<slug>`
- **`apps/stats`** — redirects the stats subdomain to `pax-vault.f3nation.com/stats/region/<id>`

Both read `REGION_SLUG`, `REGION_ID`, and `REGION_NAME` from environment variables at runtime (`export const dynamic = "force-dynamic"`).

Shared redirect logic lives in `packages/redirects/src/index.ts`. A `requireEnv()` helper throws clear errors if any variable is missing.

### Infrastructure

Deployment uses **Google Cloud Run** provisioned via **Terraform** (`infra/terraform/cloud-run/`):

- Artifact Registry for Docker images
- Two Cloud Run services (web + stats), each with its own domain mapping
- Service accounts and public invoker access
- No load balancer — uses Cloud Run's direct domain mapping (cheap and simple)

See [`infra/terraform/cloud-run/README.md`](infra/terraform/cloud-run/README.md) for the full Terraform deploy flow.

### Local development

```bash
cp .env.example .env   # fill in your region's values
pnpm install
pnpm dev
```

- Web app: http://localhost:3000
- Stats app: http://localhost:3001

### Commands

| Command             | What it does            |
| ------------------- | ----------------------- |
| `pnpm dev`          | Start both apps locally |
| `pnpm build`        | Production build        |
| `pnpm test`         | Unit tests (vitest)     |
| `pnpm test:e2e`     | E2E tests (playwright)  |
| `pnpm lint`         | ESLint                  |
| `pnpm typecheck`    | TypeScript check        |
| `pnpm format`       | Prettier auto-fix       |
| `pnpm format:check` | Prettier check (CI)     |

### Container images

- `Dockerfile.web` — multi-stage build for the web redirect service
- `Dockerfile.stats` — multi-stage build for the stats redirect service

Both produce Next.js standalone output for minimal Cloud Run images.

### Configuration files

| File                                                 | Purpose                         | Tracked?        |
| ---------------------------------------------------- | ------------------------------- | --------------- |
| `.env.example`                                       | Template for local dev env vars | Yes             |
| `.env`                                               | Your local dev env vars         | No (gitignored) |
| `infra/terraform/cloud-run/terraform.tfvars.example` | Template for Terraform config   | Yes             |
| `infra/terraform/cloud-run/terraform.tfvars`         | Your actual Terraform config    | No (gitignored) |

### Key decisions

See [`docs/adr/0001-cloud-run-domain-mapping.md`](docs/adr/0001-cloud-run-domain-mapping.md) for why we chose Cloud Run with direct domain mappings over alternatives like Firebase Hosting or an HTTPS load balancer.
