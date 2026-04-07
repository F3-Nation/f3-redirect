---
name: f3-region-gcp-terraform-deploy
description: Deploy the F3 redirect stack into a Google Cloud organization using gcloud and Terraform. Use when creating a region-owned Google Cloud project, bootstrapping gcloud or terraform if missing, pushing Cloud Run images, applying the Terraform stack, or retrieving DNS records for GoDaddy.
metadata:
  version: "2.0.0"
  argument-hint: "[region-slug]"
---

# F3 Region GCP Terraform Deploy

Use this skill when the user wants to deploy `f3-redirect` into Google Cloud with the repo's Terraform stack.

## Architecture

This repo deploys **two separate Cloud Run services** per region:

| Service   | Purpose                                                                   | Example domain         |
| --------- | ------------------------------------------------------------------------- | ---------------------- |
| **web**   | Redirects the region's apex domain to `regions.f3nation.com/<slug>`       | `f3muletown.com`       |
| **stats** | Redirects a stats subdomain to `pax-vault.f3nation.com/stats/region/<id>` | `stats.f3muletown.com` |

Each service gets its own Cloud Run domain mapping and its own DNS records. They share the same three runtime environment variables (`REGION_SLUG`, `REGION_ID`, `REGION_NAME`) but serve different redirect targets.

## Goals

1. Prefer a dedicated Google Cloud project per F3 region.
2. Keep deployment cheap and simple: Artifact Registry + 2 Cloud Run services + direct domain mappings.
3. Use `gcloud`, `docker`, and `terraform` rather than Firebase.

## First Step

Run `.claude/skills/f3-region-gcp-terraform-deploy/scripts/ensure-clis.sh` before any deployment work. It verifies `gcloud` and `terraform` are installed, installing them via Homebrew or apt if possible.

If installation cannot be completed automatically, stop and report the exact blocker.

## Collect Region Configuration (MUST prompt the user)

Before any deployment work, you MUST ask the user for all region-specific values. Do NOT guess or assume these. Ask explicitly:

1. **Region slug** — the slug on `regions.f3nation.com` (e.g., `muletown`, `marshall`)
2. **Region ID** — the numeric ID from `pax-vault.f3nation.com/stats/region/<id>` (e.g., `35838`)
3. **Region display name** — for page titles/metadata (e.g., `Muletown`, `Marshall County`)
4. **Web domain** — the apex domain for the region homepage redirect (e.g., `f3muletown.com`)
5. **Stats domain** — the subdomain for the stats redirect (e.g., `stats.f3muletown.com`)
6. **Google Cloud project ID** — or confirm the convention `f3-<region-slug>` (e.g., `f3-muletown`)
7. **Google Cloud region** — default `us-central1` unless the user says otherwise

If the user provides a region slug as an argument, use it to pre-fill defaults and ask for confirmation on the rest.

## Secrets & Configuration Management

This repo uses **two separate config files** for different purposes:

### Local development: `.env`

```bash
# .env (gitignored, for `pnpm dev`)
REGION_SLUG=muletown
REGION_ID=35838
REGION_NAME=Muletown
```

Create this from `.env.example` when the user wants to run locally.

### Cloud Run deployment: `infra/terraform/cloud-run/terraform.tfvars`

```hcl
# terraform.tfvars (gitignored, for `terraform apply`)
project_id = "f3-muletown"
region     = "us-central1"

web_service_name   = "f3-muletown-web"
stats_service_name = "f3-muletown-stats"

web_domain   = "f3muletown.com"
stats_domain = "stats.f3muletown.com"

web_image   = "us-central1-docker.pkg.dev/f3-muletown/f3-region-redirect/web:v1"
stats_image = "us-central1-docker.pkg.dev/f3-muletown/f3-region-redirect/stats:v1"

region_slug = "muletown"
region_id   = "35838"
region_name = "Muletown"
```

**Both files are gitignored.** The `.env.example` and `terraform.tfvars.example` templates are tracked; actual values are not. After collecting values from the user, write them to these files directly.

## Preferred Project Convention

Guide the user toward a dedicated project per region:

- project name: `F3 <Region Name>`
- project id: `f3-<region-slug>`
- labels:
  - `application=f3-region-redirect`
  - `region=<region-slug>`
  - `managed_by=terraform`

If the user is deploying inside an existing organization, prefer placing the project inside the appropriate folder before provisioning infra.

## Deployment Workflow

1. **Collect configuration** — prompt the user for all values listed above.
2. **Verify CLI tools** — run the `ensure-clis.sh` script.
3. **Verify GCP auth** — `gcloud auth list`, confirm the active account and org.
4. **Create the project** if it does not exist:

```bash
gcloud projects create f3-<slug> --name="F3 <Region Name>"
gcloud config set project f3-<slug>
```

5. **Enable billing and APIs**:

```bash
gcloud services enable artifactregistry.googleapis.com run.googleapis.com
```

6. **Write config files** — create both `.env` and `terraform.tfvars` with the user's values.
7. **Initialize Terraform and create Artifact Registry**:

```bash
cd infra/terraform/cloud-run
terraform init
terraform apply -target=google_artifact_registry_repository.containers
```

8. **Configure Docker auth**:

```bash
gcloud auth configure-docker <region>-docker.pkg.dev
```

9. **Build and push both images** (from repo root):

```bash
docker build -f Dockerfile.web -t <web_image> .
docker push <web_image>
docker build -f Dockerfile.stats -t <stats_image> .
docker push <stats_image>
```

10. **Apply the full Terraform stack**:

```bash
terraform apply
```

11. **Retrieve DNS records for both services**:

```bash
terraform output web_domain_mapping_records
terraform output stats_domain_mapping_records
```

12. **Report results to the user**:
    - Cloud Run service URLs (the `.run.app` URLs for immediate testing)
    - Exact DNS records for the web domain (e.g., `f3muletown.com`)
    - Exact DNS records for the stats domain (e.g., `stats.f3muletown.com`)
    - Tell the user to add those DNS records in GoDaddy (or their DNS provider) **exactly as returned** — do not paraphrase the records.

## gcloud Guidance

Useful commands:

```bash
gcloud auth list
gcloud organizations list
gcloud resource-manager folders list --organization ORGANIZATION_ID
gcloud projects describe PROJECT_ID
gcloud projects create PROJECT_ID --name="F3 Region Name"
gcloud config set project PROJECT_ID
gcloud services enable artifactregistry.googleapis.com run.googleapis.com
gcloud auth configure-docker REGION-docker.pkg.dev
```

If the user wants org/folder placement and has permissions, use:

```bash
gcloud projects create PROJECT_ID --name="F3 Region Name" --folder=FOLDER_ID
```

## Terraform Guidance

- Never commit `terraform.tfvars`, state files, plans, or `.terraform/`.
- Keep `terraform.tfvars.example` generic and checked in.
- Prefer `terraform fmt` after edits.
- Return exact Terraform outputs instead of paraphrasing DNS records.

## Repo Docs

- `README.md`
- `CLAUDE.md`
- `docs/adr/0001-cloud-run-domain-mapping.md`
- `infra/terraform/cloud-run/README.md`
