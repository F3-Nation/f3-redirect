# Runbook: Stuck Reconciler Operation

## Symptom

- **Alert:** `redirect_platform_stuck_operation=true` in Cloud Logging, routed
  to PagerDuty and `#f3-platform-alerts`.
- **Source:** the reconciler, when a single operation has been heartbeating
  the reconciler lease for **30 consecutive minutes** without completing. This
  is the hard cap on the lease heartbeat ([R5 Decision 6][decision-6], lease
  heartbeat section).
- **What the alert body says:** "Reconciler hit the 30-min heartbeat cap on
  `operation=<op>` for `domain_id=<uuid>` in `region=<us-central1|europe-west1>`.
  See runbook."

## Context

Per [R5 Decision 6][decision-6], reconciler operations that exceed the 4-minute
lease TTL run a heartbeat goroutine extending the lease every 30 seconds, up to
a **30-minute hard cap**. If the cap is hit, the reconciler:

1. Aborts the current operation cleanly (rolls back any open DB work, does not
   attempt further GCP API calls).
2. Logs `CRITICAL` with label `redirect_platform_stuck_operation=true` and the
   `operation` label set to whichever step was running.
3. Exits the process.

The next scheduled run (5 minutes later, whichever region gets the lease) picks
up the same domain from whatever state the short DB transactions left it in.
No manual kill is needed in most cases.

## Likely causes

1. **Stuck GCP API call.** Certificate Manager occasionally hangs during cert
   provisioning — a `Certificate.create` can sit in `PROVISIONING` for well over
   30 minutes without returning, or a `DnsAuthorization.create` can hang if
   Google's DNS validation is slow.
2. **Neon Postgres unreachable.** The heartbeat is a Postgres UPDATE; if Neon
   is unreachable, the heartbeat silently fails and the lease expires. The
   reconciler detects the zero-row UPDATE and aborts.
3. **Runaway retry loop in reconciler code.** A bug that retries an API call
   without backing off, burning heartbeat cycles.
4. **Long-running SNI probe.** Decision 4's probe can take a minute or two per
   round with retries — this should never hit the 30-min cap unless the LB or
   runtime is itself unreachable.

## Diagnostic steps

1. **Read the Cloud Logging entry's `operation` label** to identify which
   reconciler operation was running. Possible values come from Decision 6's
   per-cycle op list:
   - `dns_challenge_validation`
   - `cert_provisioning`
   - `sni_probe`
   - `post_cutover_dns_verification`
   - `active_health`
   - `tombstone_cleanup`
   - `quarantine_release_drift_check`

2. **Confirm the reconciler Cloud Run job has in fact exited.** Both regions:

   ```bash
   gcloud run jobs executions list \
     --job=redirect-reconciler \
     --region=us-central1 \
     --project=f3-redirects \
     --limit=5

   gcloud run jobs executions list \
     --job=redirect-reconciler \
     --region=europe-west1 \
     --project=f3-redirects \
     --limit=5
   ```

   The most recent execution should show `Succeeded` or `Failed` (not
   `Running`). If it's still `Running`, the abort path did not work — manually
   cancel it with `gcloud run jobs executions cancel`.

3. **Check Neon status** at https://neonstatus.com. If Neon is reporting an
   incident, the heartbeat failure path is expected and the next cycle will
   likely hit the same wall until Neon recovers.

4. **Check Certificate Manager quota and error budget** for the `f3-redirects`
   project:

   ```bash
   gcloud logging read 'resource.type=certificate_manager_cert AND severity>=WARNING' \
     --project=f3-redirects --limit=20 --freshness=1h
   ```

   Look for quota-exceeded messages or repeated timeouts from Certificate
   Manager.

5. **Inspect the stuck domain row** in Neon:

   ```sql
   SELECT id, hostname, lifecycle_state, last_reconciled_at, reconciler_error
     FROM region_custom_domains
    WHERE id = '<domain_id>';
   ```

   Note the `lifecycle_state`. The next cycle will resume from this state.

## Recovery

- **In most cases, no action is required.** The reconciler has aborted itself.
  The next scheduled run (≤ 5 minutes later) picks up the same domain and
  re-runs the operation via GET-with-spec-check. If the underlying cause has
  cleared (transient GCP slowness, brief Neon blip), the operation completes
  normally.
- **If the next cycle hits the same 30-min cap on the same `domain_id` and
  `operation`, escalate.** Two consecutive stuck operations on the same row
  mean the reconciler is looping on a genuinely broken external dependency or
  a reconciler bug.
- **If Neon is in a declared incident,** leave the reconciler alone. It will
  recover on its own once Neon is back.
- **If a Certificate Manager call is genuinely wedged** (30+ min in
  `PROVISIONING` with no progress), file a Google Cloud support ticket against
  the `f3-redirects` project and include the `Certificate.name` and `operation`
  resource IDs from the reconciler's logs.

## Escalation

Page the platform lead via `#f3-platform-alerts` (`@platform-lead-oncall`) when:

- Two consecutive stuck-operation alerts fire on the same `domain_id`.
- The alert fires on the `quarantine_release_drift_check` operation (this
  should never block — it's three GETs).
- Any stuck operation happens while Certificate Manager is not reporting an
  incident and Neon is not reporting an incident.
- More than one `domain_id` hits stuck-operation alerts inside a single
  reconciler cycle. This suggests a reconciler-wide regression, not a per-row
  external dependency problem.

## See also

- [R5 Decision 6: lease heartbeat and crash recovery][decision-6]
- [Runbook: Reconciler Drift](./reconciler-drift.md)
- [Runbook: Certificate Renewal Failure](./cert-renewal-failure.md)

[decision-6]: ../plans/2026-04-14-multi-tenant-saas-refactor.md#decision-6-backend-reconciler-with-designed-concurrency-r5-rework
