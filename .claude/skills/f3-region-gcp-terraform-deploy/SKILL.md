---
name: f3-region-gcp-terraform-deploy
description: Deploy the F3 redirect stack into a Google Cloud organization using gcloud and Terraform. Use when creating a region-owned Google Cloud project, bootstrapping gcloud or terraform if missing, pushing Cloud Run images, applying the Terraform stack, or retrieving DNS records for GoDaddy.
metadata:
  version: "1.0.0"
  argument-hint: "[region-slug]"
---

# F3 Region GCP Terraform Deploy

Use this skill when the user wants to deploy `f3-redirect` into Google Cloud with the repo's Terraform stack.

## Goals

1. Prefer a dedicated Google Cloud project per F3 region.
2. Keep deployment cheap and simple: Artifact Registry + 2 Cloud Run services + direct domain mappings.
3. Use `gcloud`, `docker`, and `terraform` rather than Firebase.

## First Step

Run `.claude/skills/f3-region-gcp-terraform-deploy/scripts/ensure-clis.sh` before any deployment work. It must:

- verify `gcloud`
- verify `terraform`
- install missing tools dynamically when possible

If installation cannot be completed automatically, stop and report the exact blocker.

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

1. Confirm or derive:
   - `project_id`
   - `region`
   - `region_slug`
   - `region_id`
   - `region_name`
   - `web_domain`
   - `stats_domain`
2. Use `gcloud` to confirm the authenticated account, active org, and target project.
3. Create the regional project if it does not exist already.
4. Ensure billing and required APIs are enabled.
5. Copy `infra/terraform/cloud-run/terraform.tfvars.example` to `terraform.tfvars` if needed.
6. Fill `terraform.tfvars` with region-specific values and image tags.
7. Run:

```bash
cd infra/terraform/cloud-run
terraform init
terraform apply -target=google_artifact_registry_repository.containers
```

8. Configure Docker auth for Artifact Registry with `gcloud auth configure-docker`.
9. Build and push:

```bash
docker build -f Dockerfile.web -t <web_image> .
docker push <web_image>
docker build -f Dockerfile.stats -t <stats_image> .
docker push <stats_image>
```

10. Run `terraform apply`.
11. Return:
  - Cloud Run service URLs
  - `terraform output web_domain_mapping_records`
  - `terraform output stats_domain_mapping_records`
12. Tell the user to add those DNS records in GoDaddy exactly as returned.

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

