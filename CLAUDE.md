# CLAUDE.md — LLM Context Index

> Keep this file terse and under 200 lines. Prefer pointers over prose.

## Stack

Turbo monorepo / Next.js 16 / React 19 / TypeScript / pnpm / Docker / Terraform / Google Cloud Run

## Apps

- `apps/web` -> redirects apex/custom region domain to `https://regions.f3nation.com/<REGION_SLUG>`
- `apps/stats` -> redirects stats subdomain to `https://pax-vault.f3nation.com/stats/region/<REGION_ID>`
- shared env parsing/URL builders: `packages/redirects/src/index.ts`

## Runtime Env

Required for both services:

- `REGION_SLUG`
- `REGION_ID`
- `REGION_NAME`

## Key Files

- `README.md` -> repo overview + local/dev + deployment entrypoint
- `infra/terraform/cloud-run/README.md` -> exact Google Cloud deployment flow
- `infra/terraform/cloud-run/main.tf` -> Artifact Registry, Cloud Run services, domain mappings
- `infra/terraform/cloud-run/terraform.tfvars.example` -> region-specific config template
- `Dockerfile.web` -> Cloud Run image for `apps/web`
- `Dockerfile.stats` -> Cloud Run image for `apps/stats`
- `docs/adr/0001-cloud-run-domain-mapping.md` -> decision rationale

## Commands

```bash
pnpm install
pnpm dev
pnpm build
pnpm lint
pnpm typecheck
pnpm test
pnpm test:e2e
```

Terraform:

```bash
cd infra/terraform/cloud-run
terraform init
terraform apply -target=google_artifact_registry_repository.containers
terraform apply
terraform output web_domain_mapping_records
terraform output stats_domain_mapping_records
```

## Deployment Notes

- Preferred path is direct Cloud Run domain mapping, not Firebase and not an HTTPS load balancer.
- This is optimized for cheap/simple regional deployments.
- Cloud Run domain mapping requires verified domain ownership in Google Search Console.
- DNS records for GoDaddy come from Terraform outputs after the domain mappings exist.

## Local Skill

- `.claude/skills/f3-region-gcp-terraform-deploy/SKILL.md`
  Use for project creation, CLI bootstrap, Terraform apply flow, Cloud Run domain mapping, and GoDaddy DNS handoff.

