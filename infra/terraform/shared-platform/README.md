# `shared-platform` Terraform module

Phase 0 infrastructure for the F3 multi-tenant redirect platform (R5). This
module provisions the **shared** GCP resources that every tenant shares — the
load balancer, the cert map, the static IPs, the service accounts, the API
enablement, and the alert policies that route reconciler-emitted log entries
to PagerDuty and Slack.

## What this module provisions

- **API enablement** for Cloud Run, Compute Engine, Certificate Manager,
  Artifact Registry, Cloud Scheduler, Cloud Logging, Cloud Monitoring, and
  Secret Manager.
- **Global external HTTPS Load Balancer shell** — static IPv4 + IPv6, a
  placeholder backend service (no backends attached yet), a URL map, a target
  HTTPS proxy, and two forwarding rules (one per IP family). See
  [R5 Decision 2][decision-2].
- **Certificate Manager cert map** — an empty `redirect-platform-cert-map`
  resource. Tenant `CertificateMapEntry` records are added by the reconciler
  at runtime per [Decision 6][decision-6], not by Terraform.
- **Three service accounts** — `redirect-runtime`, `redirect-reconciler`,
  `redirect-admin-ui` — with GCP IAM roles scoped per [Decision 8][decision-8].
  Each comment in `service_accounts.tf` documents the intentional omissions.
- **Four Secret Manager secrets** for Neon connection strings —
  `neon-redirect-runtime-url`, `neon-redirect-reconciler-url`,
  `neon-redirect-admin-ui-url`, and `neon-redirect-platform-admin-url`. The
  secrets are created empty by Terraform; the first version is written
  out-of-band via `scripts/bootstrap-secrets.sh` (see "Secret bootstrap" below).
  Per-secret `roles/secretmanager.secretAccessor` bindings scope each Cloud
  Run service account to exactly one secret.
- **Log-based alert policies** for the three R5 alert classes:
  `redirect_platform_drift`, `redirect_platform_stuck_operation`,
  `redirect_platform_cert_renewal`. Each policy wires its documentation field
  to the corresponding runbook URL in `docs/runbooks/`.

## What this module does NOT provision

- **Cloud Run services and jobs.** The runtime service and the reconciler
  job are in a separate module (F3R5_004). This module only creates the
  network shell and the service accounts those workloads run as.
- **Neon Postgres.** The `f3-redirect-platform` Neon project is managed
  outside Terraform — see Decision 8 for the project layout and R5 Phase 0
  Neon section for the bootstrap migration.
- **Secret *versions*.** Terraform creates the four Secret Manager secret
  shells and IAM bindings, but it never writes the raw Neon passwords. The
  first version of each secret is added manually via
  `scripts/bootstrap-secrets.sh` — see "Secret bootstrap" below.
- **Cloud Monitoring uptime checks.** R5 replaces uptime checks with a
  reconciler-side SNI probe ([Decision 4][decision-4]). Do not re-add uptime
  check resources to this module.
- **Pub/Sub.** R3/R4/R5 removed Pub/Sub from the cache path entirely. Do not
  re-add Pub/Sub topics or subscriptions.

## Backend state

Remote state lives in a GCS bucket in the `f3-redirects` project. The default
bucket in `providers.tf` is `f3-redirects-tfstate`. Bucket creation is
out-of-band — create it once, enable versioning, set uniform bucket-level
access, and lock it down to the principal that applies this module:

```bash
gcloud storage buckets create gs://f3-redirects-tfstate \
  --project=f3-redirects \
  --location=us \
  --uniform-bucket-level-access
gcloud storage buckets update gs://f3-redirects-tfstate \
  --versioning
```

To override the bucket at init time (e.g. for a non-default environment):

```bash
terraform init -backend-config="bucket=<other-bucket>"
```

## Required IAM on the applying principal

- **First apply:** `roles/owner` on the `f3-redirects` project. The first
  apply creates service accounts, log-based metrics, and IAM bindings, which
  each require broad permissions that narrower predefined roles don't bundle.
- **Subsequent applies:** a narrower set of `roles/compute.loadBalancerAdmin`,
  `roles/certificatemanager.editor`, `roles/iam.serviceAccountAdmin`,
  `roles/monitoring.editor`, `roles/logging.configWriter`, and
  `roles/serviceusage.serviceUsageAdmin` is sufficient. Drop `roles/owner`
  from the applying principal once the shell is in place.

## Usage

```bash
cd infra/terraform/shared-platform

# Initial backend init (or reinit after changing backend config)
terraform init

# Preview
terraform plan \
  -var="pagerduty_webhook_url=https://events.pagerduty.com/integration/<token>/enqueue" \
  -var="slack_webhook_url=https://hooks.slack.com/services/<token>"

# Apply
terraform apply \
  -var="pagerduty_webhook_url=..." \
  -var="slack_webhook_url=..."
```

Recommended pattern: put the sensitive webhook URLs in a gitignored
`terraform.tfvars` (the module's `.gitignore` rules exclude `*.tfvars` already)
and run `terraform apply` without inline vars.

## Verification after first apply

```bash
terraform output lb_ipv4_address
terraform output lb_ipv6_address
terraform output cert_map_name
terraform output reconciler_service_account_email
```

Then sanity-check from the GCP console:

- Compute Engine → Load balancing → `redirect-lb-*` resources exist.
- Certificate Manager → Certificate maps → `redirect-platform-cert-map` is
  empty and attached to the target-https-proxy.
- IAM → the three `redirect-*@f3-redirects.iam.gserviceaccount.com` service
  accounts exist with exactly the expected roles.
- Logging → Log-based metrics → the three `redirect_platform_*` metrics exist.
- Monitoring → Alerting → the three alert policies exist, both notification
  channels attached, documentation field renders the runbook URL.

## Secret bootstrap

After the first `terraform apply`, the four Neon connection-string secrets
exist but are empty — Cloud Run services will fail to start until a version
is written. This is intentional: Terraform must never see the raw Neon
passwords.

### 1. Obtain the four Neon connection strings

Grab the pooled connection strings for the four Postgres roles in the
`f3-redirect-platform` Neon project from the Neon console. Use the
**pooled** host (not the direct host) and append `?sslmode=require`. See
the [Neon connection-string docs][neon-conn] for details on pooled vs.
direct endpoints.

The four roles map to the four secrets as documented in Decision 8:

| Neon role | Secret name |
|---|---|
| `redirect_runtime` | `neon-redirect-runtime-url` |
| `redirect_reconciler` | `neon-redirect-reconciler-url` |
| `redirect_admin_ui` | `neon-redirect-admin-ui-url` |
| `platform_admin` (migrations only) | `neon-redirect-platform-admin-url` |

### 2. Run `bootstrap-secrets.sh`

```bash
cd infra/terraform/shared-platform

# Option A: env vars (recommended — keeps the values out of shell history)
NEON_RUNTIME_URL='postgresql://redirect_runtime:...sslmode=require' \
NEON_RECONCILER_URL='postgresql://redirect_reconciler:...sslmode=require' \
NEON_ADMIN_UI_URL='postgresql://redirect_admin_ui:...sslmode=require' \
NEON_PLATFORM_ADMIN_URL='postgresql://platform_admin:...sslmode=require' \
  ./scripts/bootstrap-secrets.sh

# Option B: positional args
./scripts/bootstrap-secrets.sh \
  'postgresql://redirect_runtime:...' \
  'postgresql://redirect_reconciler:...' \
  'postgresql://redirect_admin_ui:...' \
  'postgresql://platform_admin:...'
```

The script validates each URL starts with `postgresql://` and contains
`sslmode=require`, refuses to overwrite if any secret already has a version
(pass `--force` to rotate), and prints only secret names and version numbers
— never the values. Run `./scripts/bootstrap-secrets.sh --help` for details.

### 3. Inspect in the GCP console

The secrets live under
**GCP Console → Security → Secret Manager → `f3-redirects` project**.
You should see four secrets (`neon-redirect-*-url`) labeled
`platform=f3-redirect`, each with one enabled version after bootstrap.

### Rotation

Secret rotation is **manual** today. To rotate:

1. Rotate the Neon role password via the Neon console or API.
2. Re-run `bootstrap-secrets.sh --force` with the new connection string(s).
3. Redeploy the affected Cloud Run services and jobs — they pin a specific
   secret version at deploy time and will NOT pick up new versions on their
   own.
4. After the new revisions are serving traffic, destroy the old secret
   version(s) via `gcloud secrets versions destroy`.

Automated rotation (Neon API → Secret Manager → Cloud Run redeploy) is
tracked as a follow-up in the R5 plan and is out of scope for Phase 0.

## Pointer to the R5 plan

This module is the Terraform half of Phase 0 in
[`docs/plans/2026-04-14-multi-tenant-saas-refactor.md`][r5-plan]. The Neon
half and the Secret Manager bootstrap are documented in the same file.

The coexisting [`../cloud-run/`](../cloud-run/README.md) module is the legacy
per-region Terraform used for Muletown and Marshall deployments. It is kept
intact for the duration of the R5 migration and will be retired after Phase 4.

[decision-2]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#decision-2-global-external-https-load-balancer--cert-map
[decision-4]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#decision-4-reconciler-side-sni-probe-before-cutover-r5-rewrite
[decision-6]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#decision-6-backend-reconciler-with-designed-concurrency-r5-rework
[decision-8]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md#decision-8-security-model-r3-expansion
[r5-plan]: ../../../docs/plans/2026-04-14-multi-tenant-saas-refactor.md
[neon-conn]: https://neon.tech/docs/connect/connect-from-any-app
