# F3 Redirect

A multi-tenant service that redirects **custom domains** to arbitrary destination
URLs. A user signs in, registers a custom domain plus a destination URL, gets DNS
instructions, and once their domain points at us every request to it returns a
301/302 to their destination.

The first two mappings to support:

| Source                  | Destination                                       | DNS shape                              |
| ----------------------- | ------------------------------------------------- | -------------------------------------- |
| `f3muletown.com`        | `https://regions.f3nation.com/muletown`           | **apex** → A record to a static IP     |
| `stats.f3muletown.com`  | `https://pax-vault.f3nation.com/stats/region/35838` | **subdomain** → CNAME to our hostname  |

These two exercise both DNS shapes from day one: the apex domain can't CNAME (needs
an A record to a reserved static IP), while the subdomain can CNAME normally.

> **Status: clean slate.** This repository has been reset. The previous
> TypeScript/Next.js + Cloud Run implementation (per-region redirect apps) has
> been removed to make room for a re-imagined, multi-tenant architecture. The
> implementation lands in a follow-up PR — see **Planned architecture** below.

## Planned architecture

The first goal is to **prove out the concept** with a Go backend only. No
web frontend yet — administration happens over a **CLI** (optionally wrapped by
Claude Code skills for ergonomic local-dev use). A TypeScript management UI is
explicitly deferred until the core works.

- **Redirect tier (Go).** Reads the `Host` header on each request, looks up the
  target mapping, and emits the 301/302. DNS only routes the request to us; the
  redirect itself is an HTTP response we produce. This tier also handles on-demand
  TLS (see below).
- **Admin CLI (Go).** Adds/lists/removes tenant mappings
  (`hostname → target URL`) and prints the DNS instructions a tenant needs —
  typically a CNAME from their domain to our hostname plus a TXT record for
  ownership verification before activation. Claude Code skills may wrap this CLI
  for convenience.
- **Storage — a flat file in GCS. No database.** Keep it ridiculously simple: the
  mappings live in a single minimal config file (e.g. JSON) in a Google Cloud
  Storage bucket. The redirect tier reads it to resolve hosts; the on-demand TLS
  decision function checks it to confirm a hostname is registered before issuing a
  cert; the CLI edits it. We can graduate to a database later if we ever need to.
- **TypeScript frontend — deferred.** A multi-tenant management UI is out of scope
  for now; the CLI covers administration while we validate the approach.

### Why Go for the redirect tier

The hard part of this system is issuing valid TLS certificates **on demand** for
domains we don't own. Go has the most mature ecosystem for this:

- **[CertMagic](https://github.com/caddyserver/certmagic)** (the ACME engine
  behind Caddy) provides automatic on-demand TLS as a library — embedded in our
  own Go HTTP server so we keep full control of the redirect logic.
- The workload is **network/TLS-bound, not CPU-bound**, so Rust's performance and
  memory advantages don't move the needle here.

### Constraints the implementation must honor

1. **Gate cert issuance on a registry check.** CertMagic's on-demand decision
   function must confirm the incoming hostname is in the GCS config file before
   issuing a cert — otherwise anyone pointing a domain at our IP could exhaust our
   Let's Encrypt rate limits.
2. **Shared cert storage, never the filesystem default.** Instances are
   ephemeral/autoscaled, so certs live in a shared backend (a GCS storage adapter)
   and are reused across instances and restarts. Keeping both the config file and
   the certs in GCS means no database anywhere.
3. **We terminate TLS ourselves**, so we own port 443 directly. This rules out
   Cloud Run for the redirect tier (it terminates TLS for us); the redirect tier
   deploys on **GCE (managed instance group) or GKE**.
4. **Apex/root domains can't CNAME.** Root-domain redirects need ALIAS/ANAME or an
   A record to a static IP — handled in the DNS-instruction logic.

## What's in this repo today

Only repository scaffolding survives the reset:

| Path                               | Purpose                                 |
| ---------------------------------- | --------------------------------------- |
| `.github/workflows/ci.yaml`        | CI (Go-aware; no-ops until code lands)  |
| `.github/CODEOWNERS`               | Code ownership                          |
| `.github/pull_request_template.md` | PR template                             |
| `.gitignore`                       | Go + Node + Terraform ignores           |
| `README.md`                        | This file                               |
