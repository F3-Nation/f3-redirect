# ADR 0001: Deploy F3 Region Redirects with Cloud Run and Direct Domain Mapping

## Status

Accepted on 2026-04-07

## Context

`f3-redirect` is a reusable redirect repo intended for many regional F3 deployments. Each region needs:

- isolated Google Cloud ownership
- a predictable way to inject region-specific runtime variables
- low operating cost
- minimal infrastructure and maintenance burden
- custom domains such as `f3muletown.com` and `stats.f3muletown.com`

The prior deployment guidance was Vercel-oriented and did not provide region-owned infrastructure as code. The team also wanted to avoid Firebase if possible.

## Decision

Use:

- Docker images for `apps/web` and `apps/stats`
- Artifact Registry for container storage
- one Cloud Run service per app
- Terraform for infrastructure provisioning
- direct Cloud Run domain mappings for custom domains

Do not use:

- Firebase App Hosting
- a Google Cloud HTTPS load balancer in the default path

## Why

This choice optimizes for simplicity and cost:

- regions can own a dedicated Google Cloud project
- runtime env vars are explicit in Terraform
- Cloud Run scales to zero
- no load balancer baseline cost
- no Firebase-specific operational model
- DNS handoff is straightforward because Google returns the exact required records for each mapping

## Tradeoffs

Pros:

- cheapest path to a custom-domain deployment
- smallest amount of Google Cloud infrastructure
- straightforward Terraform variable model per region
- easy to explain to regional volunteers

Cons:

- Cloud Run domain mapping is a preview capability in Google Cloud documentation
- less edge flexibility than a load balancer
- no single static IP for apex and subdomain routing

## Consequences

- deployment docs must clearly call out the preview/production tradeoff
- each region should create its own Google Cloud project
- each region must verify domain ownership before applying domain mappings
- Terraform must output Google-provided DNS records for the registrar

## Operational Pattern

1. Create or select a dedicated Google Cloud project for the region.
2. Push the `web` and `stats` images to Artifact Registry.
3. Apply Terraform for Cloud Run services and optional domain mappings.
4. Copy Terraform output DNS records into GoDaddy.
5. Re-apply Terraform when image tags or region env vars change.

## References

- `infra/terraform/cloud-run/README.md`
- `infra/terraform/cloud-run/main.tf`
- `infra/terraform/cloud-run/outputs.tf`
