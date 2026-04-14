# Runbook: Certificate Renewal Failure

## Symptom

- **Alert:** `redirect_platform_cert_renewal=true` in Cloud Logging, routed to
  PagerDuty and `#f3-platform-alerts`.
- **Source:** the reconciler's T-14 / T-7 / T-1 renewal-failure escalation
  ladder ([R5 Decision 8][decision-8]), or a direct observation of
  `Certificate.managed.state = FAILED` during the `active` health check
  (Decision 6, op 5).
- **What the alert body says:** "Cert renewal failed for `domain_id=<uuid>`,
  `hostname=<host>`, `expires_at=<timestamp>`. See runbook."

## Escalation ladder

Per [R5 Decision 8][decision-8], the reconciler watches `Certificate.managed.state`
and `Certificate.managed.authorizationAttemptInfo` during the `active` health
check. The renewal ladder fires at the following offsets from
`Certificate.expires_at`:

| Offset | Action |
|---|---|
| **T-14 days** | Warning notification in the admin UI, email to org admins on the bound org, Slack message to `#f3-platform-alerts`. `lifecycle_state` stays `active`. |
| **T-7 days** | Escalated warning. `lifecycle_state` transitions to `degraded` with `reconciler_error.recoverable_from = 'active'`. |
| **T-1 day** | Cloud Logging `CRITICAL` with label `redirect_platform_cert_renewal=true` — this is the alert that just paged you. |
| **Post-expiry** | The cert continues to serve while in `degraded` until the LB removes it. The admin UI surfaces "RENEWAL FAILED — region needs to re-verify DNS authorization CNAME." |

The important thing: **the cert stays live through post-expiry until GCLB drops
it.** You usually have hours (sometimes a day) after the T-1 alert fires to
recover without a user-visible outage, as long as you act.

## First diagnostic step — always the same

**Is the `_acme-challenge.*` CNAME still live in the region's DNS?**

The DNS authorization is what proves ownership to Certificate Manager. If the
region admin removed the CNAME after initial provisioning, renewals will fail
silently until you notice.

1. Look up the DnsAuthorization's CNAME target:

   ```bash
   gcloud certificate-manager dns-authorizations describe dns-auth-<uuid> \
     --location=global --project=f3-redirects \
     --format="value(dnsResourceRecord.name,dnsResourceRecord.type,dnsResourceRecord.data)"
   ```

   This prints the record the region must have in its DNS, something like:

   ```
   _acme-challenge.f3marshall.com  CNAME  <long-hash>.dv.goog.
   ```

2. Query the region's public DNS and compare:

   ```bash
   dig _acme-challenge.f3marshall.com CNAME +short
   ```

   - **Expected:** the same `<long-hash>.dv.goog.` value.
   - **If empty:** the CNAME is missing. Go to [If CNAME is missing](#if-cname-is-missing).
   - **If a different value:** the CNAME has been overwritten. Treat as missing.

## If CNAME is live

The ownership proof is still there, so the renewal is failing for some other
reason — most commonly Certificate Manager has not yet retried, or is retrying
against a cached DNS result.

1. In the admin UI, open the domain detail page and click **"Retry reconciliation."**
   `reconciler_error` is cleared and `lifecycle_state` moves to `active` (or
   whichever `recoverable_from` was recorded).
2. The next reconciler cycle will re-run the cert provisioning path.
3. If Certificate Manager still reports `FAILED` after the next cycle, read the
   detailed failure reason:

   ```bash
   gcloud certificate-manager certificates describe cert-<uuid> \
     --location=global --project=f3-redirects \
     --format="value(managed.state,managed.authorizationAttemptInfo[0].details,managed.authorizationAttemptInfo[0].state)"
   ```

   The `authorizationAttemptInfo[0].details` field usually explains exactly
   what Google's validator saw (e.g. "DNS resolution timed out", "got NXDOMAIN",
   "got a CNAME loop").

4. If the detail says Google saw a different value than `dig` shows you, the
   region is serving different answers from different resolvers — likely a
   split-horizon DNS setup. Escalate and involve the region admin.

## If CNAME is missing

**Do not attempt to re-provision.** The cert will keep failing until ownership
proof is restored.

1. Identify the org admin for the binding:

   ```sql
   SELECT orb.org_id, o.name, orb.bound_by_user_id
     FROM org_region_bindings orb
     JOIN region_custom_domains rcd ON rcd.org_id = orb.org_id
     JOIN orgs o ON o.id = orb.org_id
    WHERE rcd.id = '<domain_id>';
   ```

2. Contact the org admin via the channel stored in `orgs.contact_email` or via
   `#f3-platform-alerts` if they're reachable there.

3. Send them the exact CNAME record they need to re-add, copied from the
   `gcloud dns-authorizations describe` output above. Include:
   - The full record name (`_acme-challenge.<hostname>`)
   - Record type (CNAME)
   - The target value (`<long-hash>.dv.goog.`)
   - A note that CNAMEs at a domain apex are not valid — the `_acme-challenge`
     subdomain makes this safe, but check for the region admin's DNS provider
     quirks.

4. Ask them to confirm the record via `dig` or their DNS provider's UI, then
   click **"Retry reconciliation"** in the admin UI.

## If the domain itself has moved

Sometimes the renewal fails because the region has genuinely moved the hostname
to a new registrar or a new zone and didn't tell the platform. This is a
**re-registration**, not a renewal.

1. Tombstone the domain in the admin UI: click **"Delete domain"** on the
   domain detail page. The row transitions `degraded → tombstoned`, the
   reconciler tears down all three GCP resources, and the row advances to
   `quarantined` with `released_at = now() + 30 days`.
2. Wait out the 30-day quarantine. The partial unique index on `hostname`
   prevents re-registration until `released`.
3. Once the row reaches `released`, the region can re-register the hostname
   through the normal onboarding flow against the new DNS setup.
4. If the region needs the hostname sooner than 30 days, a platform super-admin
   can shorten the quarantine via a manual DB UPDATE — but this is a break-glass
   action that must be recorded in `region_custom_domain_events` with
   `details.justification`.

## See also

- [R5 Decision 8: Security Model — renewal-failure handling][decision-8]
- [Runbook: Reconciler Drift](./reconciler-drift.md)
- [Runbook: Stuck Operation](./stuck-operation.md)

[decision-8]: ../plans/2026-04-14-multi-tenant-saas-refactor.md#decision-8-security-model-r3-expansion
