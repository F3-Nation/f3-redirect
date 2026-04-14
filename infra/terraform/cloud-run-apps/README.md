# `cloud-run-apps` Terraform module

Phase 0 application plane for the F3 multi-tenant redirect platform (R5).
This module provisions the Cloud Run services, the Cloud Run job, the
Cloud Scheduler cron, and the serverless NEG attachment that sits behind
the shared HTTPS LB. It is the **application** half of the Phase 0
infrastructure — `shared-platform` owns the network and IAM shell, this
module owns the workloads.

See [F3R5_004 in the R5 plan][r5-plan-f3r5-004] for the originating task.

## What this module provisions

- **`redirect-runtime`** — a Cloud Run v2 service in `us-central1` running
  the Next.js redirect runtime. `min_instance_count = 1` per [Decision 3][d3].
  Ingress is `INTERNAL_AND_CLOUD_LOAD_BALANCING`, so the only public path
  is through the LB.
- **`redirect-reconciler-<region>`** — a Cloud Run v2 **job** deployed in
  **two regions** (`us-central1` and `europe-west1`) per [Decision 6][d6],
  for SNI probe diversity.
- **`redirect-reconciler-cron-<region>`** — a Cloud Scheduler job per region
  that triggers the Cloud Run job every 5 minutes via the Cloud Run v2 API
  with an OAuth-token-authenticated HTTP target.
- **`redirect-admin`** — a Cloud Run v2 service in `us-central1` running
  the Next.js admin UI. Public ingress, SSO at the app layer per
  [Decision 5][d5].
- **`redirect-runtime-neg`** — a SERVERLESS network endpoint group pointing
  at the runtime service.
- An imperative `null_resource` that attaches the NEG to the shared LB
  backend service (`redirect-default-backend`) via `gcloud`. See the
  "Backend service wiring" section below for why this is not pure
  Terraform.

## What this module does NOT provision

- **Load balancer, cert map, static IPs, service accounts, Secret Manager
  secrets, alert policies** — those are in `shared-platform`.
- **Container images.** The Cloud Run resources reference images by tag,
  but CI/CD builds-and-pushes the actual images. First apply will create
  the Cloud Run resources successfully but the revisions will fail to
  start until images exist under the expected tags in Artifact Registry.
- **Artifact Registry repo.** Creation of the `f3-redirect-platform` repo
  is done out-of-band via `gcloud artifacts repositories create` (or a
  future `shared-platform` addition).
- **The admin UI's custom hostname + cert.** `redirect-admin.f3nation.com`
  (or equivalent) is wired out of scope for F3R5_004.

## Required inputs from `shared-platform`

Pass these as tfvars (or let the caller wire them from
`terraform output -json` on shared-platform). Their canonical source is
[`../shared-platform/outputs.tf`][shared-outputs].

| Variable | Source output |
|---|---|
| `runtime_service_account_email` | `runtime_service_account_email` |
| `reconciler_service_account_email` | `reconciler_service_account_email` |
| `admin_ui_service_account_email` | `admin_ui_service_account_email` |
| `cert_map_name` | `cert_map_name` |
| `cert_map_resource_id` | `cert_map_resource_id` |
| `lb_ipv4_address` | `lb_ipv4_address` |
| `neon_redirect_runtime_secret_name` | `neon_redirect_runtime_secret_name` |
| `neon_redirect_reconciler_secret_name` | `neon_redirect_reconciler_secret_name` |
| `neon_redirect_admin_ui_secret_name` | `neon_redirect_admin_ui_secret_name` |

The LB backend service name is read automatically via a
`terraform_remote_state` data source against the shared-platform state
(bucket + prefix set by `shared_platform_state_bucket` and
`shared_platform_state_prefix`, which default to the same values
shared-platform uses).

## Backend service wiring

The Terraform google provider has no per-backend sub-resource on
`google_compute_backend_service`. Backends are an in-line attribute on
the backend service resource itself. That leaves two real options:

- **(a)** Manage the backend service in ONE module — either here or in
  `shared-platform` — and keep everything in one state.
- **(b)** Split: shared-platform owns the backend service shell,
  cloud-run-apps owns the NEG and imperatively attaches it via `gcloud`.

**We picked (b).** Option (a) would force one of two unacceptable
outcomes:

- **Backend service in this module.** Then the URL map, target-https-proxy,
  and forwarding rules in shared-platform would need to reference this
  module's output, inverting the dependency and turning every Cloud Run
  deploy into a shared-platform apply.
- **Cloud Run in shared-platform.** Then every app revision change would
  churn state in the same module that manages the LB and cert map —
  unacceptable blast radius.

Option (b) keeps state cleanly split at the cost of one imperative
`gcloud` call. The shared-platform placeholder is marked with
`lifecycle { ignore_changes = [backend] }` so re-applies of
shared-platform never strip the attachment.

The attach/detach lives in [`lb_backend.tf`][lb-backend] as a
`null_resource` with a trigger keyed to the NEG self-link, making
re-applies idempotent. Destroying the module cleanly detaches the NEG.

## First-apply order

1. `cd infra/terraform/shared-platform && terraform apply` — creates the
   LB shell, cert map, SAs, and Secret Manager secrets.
2. `./scripts/bootstrap-secrets.sh` — writes the four Neon connection
   strings into Secret Manager (Terraform never sees the values).
3. *(out-of-band)* `gcloud artifacts repositories create f3-redirect-platform`
   in `us-central1`.
4. *(out-of-band)* Build and push the three images under the expected tags:
   - `us-central1-docker.pkg.dev/f3-redirects/f3-redirect-platform/runtime:<tag>`
   - `us-central1-docker.pkg.dev/f3-redirects/f3-redirect-platform/reconciler:<tag>`
   - `us-central1-docker.pkg.dev/f3-redirects/f3-redirect-platform/redirect-admin:<tag>`
5. `cd infra/terraform/cloud-run-apps && terraform apply \
      -var="runtime_image_tag=<tag>" \
      -var="reconciler_image_tag=<tag>" \
      -var="admin_ui_image_tag=<tag>" \
      ...`

On first apply the Cloud Run resources come up, the NEG is created, and
the `null_resource` runs `gcloud compute backend-services add-backend`
against `redirect-default-backend`. After that, the global LB forwards
traffic to the runtime service.

## Deploy flow

Ongoing deploys only touch this module — shared-platform stays frozen:

```bash
# Build + push
docker build -t us-central1-docker.pkg.dev/f3-redirects/f3-redirect-platform/runtime:v1.2.3 .
docker push us-central1-docker.pkg.dev/f3-redirects/f3-redirect-platform/runtime:v1.2.3

# Apply (only touches cloud-run-apps state)
cd infra/terraform/cloud-run-apps
terraform apply -var="runtime_image_tag=v1.2.3"
```

Apply order is invariant regardless of which app is being deployed —
cloud-run-apps will diff only the container revisions, not the LB or
NEG or cron.

## Required IAM on the applying principal

Beyond the shared-platform IAM, the principal applying this module needs:

- `roles/run.admin` on the project — creates Cloud Run services and jobs.
- `roles/iam.serviceAccountUser` on the three SAs managed by
  shared-platform — deploying a Cloud Run revision attaches the SA.
- `roles/cloudscheduler.admin` on the project — creates scheduler jobs.
- `roles/compute.loadBalancerAdmin` — the `gcloud` attach step in
  `lb_backend.tf` modifies the shared backend service.
- `roles/compute.networkAdmin` on the project — creates the NEG.
- `gcloud` on `$PATH` of the applying machine, authenticated as the same
  principal that runs `terraform apply`.

## Verification after apply

```bash
terraform output runtime_service_url
terraform output reconciler_job_names
terraform output admin_ui_service_url

# Sanity-check the NEG attachment:
gcloud compute backend-services describe redirect-default-backend \
  --global --project f3-redirects \
  --format="value(backends[].group)"
```

The output of the last command should include the NEG URL
`.../networkEndpointGroups/redirect-runtime-neg`.

## Pointer to the R5 plan

This module is the Terraform half of [F3R5_004][r5-plan-f3r5-004] in the
[R5 multi-tenant SaaS refactor plan][r5-plan].

[d3]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#decision-3-single-shared-cloud-run-runtime-service
[d5]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#decision-5
[d6]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#decision-6-backend-reconciler-with-designed-concurrency-r5-rework
[r5-plan]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md
[r5-plan-f3r5-004]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#f3r5_004
[shared-outputs]: ../shared-platform/outputs.tf
[lb-backend]: lb_backend.tf
