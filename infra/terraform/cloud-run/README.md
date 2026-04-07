# Cloud Run Terraform

This Terraform stack provisions the minimal Google Cloud setup for F3 region redirects without Firebase and without a load balancer:

- an Artifact Registry Docker repository
- one Cloud Run service for `apps/web`
- one Cloud Run service for `apps/stats`
- runtime service accounts
- public invoker access by default
- optional direct Cloud Run custom-domain mappings for each service

## Region-specific environment variables

The app runtime contract is intentionally small and matches the generic redirect repo behavior:

- `REGION_SLUG`
- `REGION_ID`
- `REGION_NAME`

Every region sets its own values in `terraform.tfvars`.

## Important tradeoff

This is the cheap and simple path, but Google currently documents Cloud Run domain mapping as a preview capability and says it is not recommended for production services:

- https://cloud.google.com/run/docs/mapping-custom-domains

For lightweight region redirect sites, that tradeoff may be acceptable. If a region wants a more formal production edge later, they can move to an HTTPS load balancer in front of the same Cloud Run services.

## Prerequisites

1. Install Terraform 1.5+.
2. Install the Google Cloud SDK.
3. Authenticate with Google Cloud:

```bash
gcloud auth application-default login
gcloud auth login
```

4. Create or choose a Google Cloud project.
5. Verify the base domain in Google Search Console before creating domain mappings.

Examples:

- to map `f3muletown.com` and `stats.f3muletown.com`, verify `f3muletown.com`
- to map `f3marshall.com` and `stats.f3marshall.com`, verify `f3marshall.com`

## Deploy flow

1. Copy the example variables:

```bash
cd infra/terraform/cloud-run
cp terraform.tfvars.example terraform.tfvars
```

2. Edit `terraform.tfvars` for your project, region, service names, image tags, region env vars, and optional domains.

3. Initialize Terraform:

```bash
terraform init
```

4. Create only the Artifact Registry repository first:

```bash
terraform apply -target=google_artifact_registry_repository.containers
```

5. Configure Docker auth for Artifact Registry:

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
```

Use your own Terraform `region` in place of `us-central1` if different.

6. Build and push the web image from the repo root:

```bash
docker build -f Dockerfile.web -t us-central1-docker.pkg.dev/my-region-project/f3-region-redirect/web:initial .
docker push us-central1-docker.pkg.dev/my-region-project/f3-region-redirect/web:initial
```

7. Build and push the stats image from the repo root:

```bash
docker build -f Dockerfile.stats -t us-central1-docker.pkg.dev/my-region-project/f3-region-redirect/stats:initial .
docker push us-central1-docker.pkg.dev/my-region-project/f3-region-redirect/stats:initial
```

8. Apply the full stack:

```bash
terraform apply
```

If `web_domain` or `stats_domain` are set, Terraform also creates direct Cloud Run domain mappings.

## DNS records for GoDaddy

After `terraform apply`, inspect the outputs:

```bash
terraform output web_domain_mapping_records
terraform output stats_domain_mapping_records
```

Google returns the exact DNS records you need to create in GoDaddy. Copy those records as-is.

Common patterns:

- apex domains such as `f3muletown.com` often require `A` or `AAAA` records
- subdomains such as `stats.f3muletown.com` often use a `CNAME`

Do not guess the values. Use the Terraform outputs from your actual mapping.

## Updating a region

1. Build and push a new web image tag.
2. Build and push a new stats image tag.
3. Update `web_image` and `stats_image` in `terraform.tfvars`.
4. Run `terraform apply`.
