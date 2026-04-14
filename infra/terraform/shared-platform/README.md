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
- **Secret Manager secrets.** The three Neon connection strings
  (`neon-redirect-runtime-url`, `neon-redirect-reconciler-url`,
  `neon-redirect-admin-ui-url`) are bootstrapped manually in F3R5_005. This
  module only grants the `secretmanager.googleapis.com` API; the secrets and
  their IAM bindings are added alongside the Cloud Run resources in F3R5_004.
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
