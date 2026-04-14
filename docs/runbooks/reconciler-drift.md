# Runbook: Reconciler Drift

## Symptom

- **Alert:** `redirect_platform_drift=true` in Cloud Logging, routed to PagerDuty
  via the `redirect_platform_drift` alert policy, and posted to `#f3-platform-alerts`
  in Slack.
- **Severity:** CRITICAL.
- **Source:** the reconciler Cloud Run job running in either `us-central1` or
  `europe-west1`. The log entry is emitted at severity `CRITICAL` with a structured
  JSON payload and the `redirect_platform_drift` label.
- **What the alert body says:** "Reconciler halted on drift for
  `domain_id=<uuid>`. See runbook." with a link to this file.

## Context

Per [R5 Decision 6][decision-6], the reconciler uses GET-with-spec-check before
any GCP mutation and **halts on mismatch rather than auto-repairing**. Automated
destruction of a live cert resource could produce a cert-provisioning storm or
live traffic outage, so drift is always treated as a bug that requires human
investigation. This runbook walks you through the investigation.

The drifted domain row has already been transitioned to `lifecycle_state =
'degraded'` with a structured `reconciler_error` JSON payload. The reconciler
will not touch the row again until a platform super-admin acknowledges the
drift in the admin UI.

## Diagnostic steps

1. **Open the triggered Cloud Logging entry.** Read the `jsonPayload`. It contains:
   - `drift_kind` — one of `spec_mismatch`, `orphan_resource`, `unexpected_state`
   - `resource_type` — `DnsAuthorization`, `Certificate`, or `CertificateMapEntry`
   - `resource_name` — the deterministic name, e.g. `cert-<uuid>`
   - `observed_spec` — the GCP GET response that the reconciler saw
   - `expected_spec` — what the reconciler would have created or expected
   - `recoverable_from` — the transient state the domain should return to on retry
   - `detected_at` — ISO timestamp of detection
   - `reconciler_run_id` — ties back to `region_custom_domain_events.details.reconciler_run_id`
   - `domain_id` — UUID of the `region_custom_domains` row

2. **Resolve `domain_id` to a domain row.** Open the admin UI at
   `https://redirect-admin.f3nation.com/domains/<domain_id>` or query Neon directly:

   ```sql
   SELECT id, hostname, org_id, lifecycle_state, reconciler_error
     FROM region_custom_domains
    WHERE id = '<domain_id>';
   ```

3. **Confirm the current `lifecycle_state`.** It should be `degraded`. If it is
   not, the alert may be stale — check `last_reconciled_at` and whether a more
   recent reconciler cycle has touched the row.

4. **GET the GCP resource yourself** using `gcloud` against the `f3-redirects`
   project. Do this from a shell authenticated as a platform admin:

   ```bash
   gcloud config set project f3-redirects

   # DNS Authorization
   gcloud certificate-manager dns-authorizations describe dns-auth-<uuid> \
     --location=global

   # Certificate
   gcloud certificate-manager certificates describe cert-<uuid> \
     --location=global

   # Certificate Map Entry (on the shared redirect-platform-cert-map)
   gcloud certificate-manager maps entries describe cme-<uuid> \
     --map=redirect-platform-cert-map \
     --location=global
   ```

   Compare what you see against `observed_spec` in the alert payload. If they
   differ, something else mutated the resource between detection and now.

## Recovery by `drift_kind`

### `spec_mismatch`

The reconciler found a GCP resource at the deterministic name whose spec does
not match what the reconciler would have created.

- **If the observed spec is correct and the expected spec is wrong,** the
  reconciler has a bug. File a platform ticket with the log entry attached.
  Ask a platform super-admin to mark the drift acknowledged in the admin UI
  (this is a separate endpoint that writes an audit event). Only after
  acknowledgement can the "Retry reconciliation" button be clicked.
- **If the observed spec is wrong,** someone (or something) mutated the GCP
  resource outside the reconciler. Either manually correct the mutation or
  delete the GCP resource so the reconciler can re-create it:

  ```bash
  gcloud certificate-manager certificates delete cert-<uuid> --location=global
  ```

  Then click **"Retry reconciliation"** in the admin UI. `reconciler_error`
  will be cleared and `lifecycle_state` set to
  `reconciler_error.recoverable_from`.

### `orphan_resource`

The `quarantined → released` drift check (Decision 6, op 7) found a leftover
GCP resource that should have been deleted during the tombstone cleanup phase.

1. Identify which resource is the orphan from `resource_type` + `resource_name`
   in the alert.
2. Delete it manually:

   ```bash
   # for cme-<uuid>
   gcloud certificate-manager maps entries delete cme-<uuid> \
     --map=redirect-platform-cert-map --location=global

   # for cert-<uuid>
   gcloud certificate-manager certificates delete cert-<uuid> --location=global

   # for dns-auth-<uuid>
   gcloud certificate-manager dns-authorizations delete dns-auth-<uuid> \
     --location=global
   ```

3. Verify all three deterministic names return 404 via a follow-up GET.
4. Click **"Retry release"** in the admin UI. The reconciler will re-run the
   drift check and advance the row to `released` on success.

### `unexpected_state`

The reconciler observed a GCP resource state the state machine did not account
for (e.g., a `Certificate` in a reported state the spec-check code does not
recognize).

- **Escalate immediately.** This typically indicates either a Certificate
  Manager API change or manual intervention outside the reconciler that left
  the resource in an unusual state.
- Do NOT attempt to `gcloud ... delete` without talking to the platform lead —
  it may be a case the reconciler can handle once the state machine is updated.
- File a platform ticket with the full `observed_spec` payload.

## Escalation path

If the above steps do not clear the alert within 30 minutes, or if the same
drift reappears on the next reconciler cycle, page the **platform lead** via
`#f3-platform-alerts` in Slack (`@platform-lead-oncall`) and attach:

- The original Cloud Logging entry
- The output of every `gcloud certificate-manager ... describe` you ran
- The current row in `region_custom_domains` as JSON

Two consecutive drift alerts on the same `domain_id` always warrant escalation —
do not loop on "retry reconciliation" expecting different results.

## See also

- [R5 Decision 6: Backend Reconciler with Designed Concurrency][decision-6]
- [Runbook: Stuck Operation](./stuck-operation.md)
- [Runbook: Certificate Renewal Failure](./cert-renewal-failure.md)

[decision-6]: ../plans/2026-04-14-multi-tenant-saas-refactor.md#decision-6-backend-reconciler-with-designed-concurrency-r5-rework
