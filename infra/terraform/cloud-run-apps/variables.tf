# Inputs for the cloud-run-apps module.
#
# The caller wires each value explicitly from shared-platform's outputs so
# this module has no hard dependency on shared-platform's state location.
# The single exception is the LB backend service lookup in `lb_backend.tf`,
# which uses a `terraform_remote_state` data source configured via the
# `shared_platform_state_bucket` / `shared_platform_state_prefix` inputs.

variable "project_id" {
  description = "GCP project hosting the shared redirect platform."
  type        = string
  default     = "f3-redirects"
}

variable "project_number" {
  description = "GCP project number for f3-redirects. Used by IAM bindings that require the numeric form."
  type        = string
  default     = "355149658273"
}

variable "regions" {
  description = <<-EOT
    Regions where the reconciler Cloud Run job runs. Per Decision 6 the
    reconciler is deployed in two regions for probe diversity. The runtime
    Cloud Run service lives in a single region (behind the global LB) and
    is NOT controlled by this variable.
  EOT
  type        = list(string)
  default     = ["us-central1", "europe-west1"]
}

variable "runtime_region" {
  description = <<-EOT
    Single region where the runtime Cloud Run service runs. The service sits
    behind the global external HTTPS LB, so multi-region deployment would
    only duplicate warm instances without reducing latency meaningfully.
  EOT
  type        = string
  default     = "us-central1"
}

variable "admin_ui_region" {
  description = "Region where the redirect-admin Cloud Run service runs."
  type        = string
  default     = "us-central1"
}

# ---------------------------------------------------------------------------
# Wired from shared-platform outputs. The caller is expected to pass these
# explicitly (e.g. from a root tfvars file or from a CI template that reads
# `terraform output -json` on shared-platform).
# ---------------------------------------------------------------------------

variable "runtime_service_account_email" {
  description = "Email of the redirect-runtime service account (shared-platform output)."
  type        = string
}

variable "reconciler_service_account_email" {
  description = "Email of the redirect-reconciler service account (shared-platform output)."
  type        = string
}

variable "admin_ui_service_account_email" {
  description = "Email of the redirect-admin-ui service account (shared-platform output)."
  type        = string
}

variable "cert_map_name" {
  description = "Short name of the shared Certificate Manager cert map (shared-platform output)."
  type        = string
}

variable "cert_map_resource_id" {
  description = "Fully-qualified resource ID of the Certificate Manager cert map (shared-platform output)."
  type        = string
}

variable "lb_ipv4_address" {
  description = "Static IPv4 of the redirect platform LB (shared-platform output). Passed to reconciler + admin UI so the SNI probe and admin console know which target to probe."
  type        = string
}

variable "neon_redirect_runtime_secret_name" {
  description = "Short name of the runtime Neon connection-string secret (shared-platform output)."
  type        = string
}

variable "neon_redirect_reconciler_secret_name" {
  description = "Short name of the reconciler Neon connection-string secret (shared-platform output)."
  type        = string
}

variable "neon_redirect_admin_ui_secret_name" {
  description = "Short name of the admin UI Neon connection-string secret (shared-platform output)."
  type        = string
}

# ---------------------------------------------------------------------------
# Cross-module state lookup for the shared LB backend service. See
# `lb_backend.tf` for the rationale.
# ---------------------------------------------------------------------------

variable "shared_platform_state_bucket" {
  description = "GCS bucket holding the shared-platform Terraform state."
  type        = string
  default     = "f3-redirects-tfstate"
}

variable "shared_platform_state_prefix" {
  description = "Prefix under which the shared-platform Terraform state is stored (matches the backend block in shared-platform/providers.tf)."
  type        = string
  default     = "shared-platform"
}

# ---------------------------------------------------------------------------
# Container images. First apply requires these images to exist in Artifact
# Registry — see README "First-apply order".
# ---------------------------------------------------------------------------

variable "artifact_registry_repo" {
  description = "Artifact Registry Docker repo name that holds the three R5 app images."
  type        = string
  default     = "f3-redirect-platform"
}

variable "artifact_registry_region" {
  description = "Region of the Artifact Registry repo holding the R5 app images."
  type        = string
  default     = "us-central1"
}

variable "runtime_image_tag" {
  description = "Tag of the runtime image in Artifact Registry. Override per deploy (e.g. a Git SHA)."
  type        = string
  default     = "latest"
}

variable "reconciler_image_tag" {
  description = "Tag of the reconciler image in Artifact Registry. Override per deploy (e.g. a Git SHA)."
  type        = string
  default     = "latest"
}

variable "admin_ui_image_tag" {
  description = "Tag of the admin UI image in Artifact Registry. Override per deploy (e.g. a Git SHA)."
  type        = string
  default     = "latest"
}

# ---------------------------------------------------------------------------
# Admin UI env vars sourced from F3R5_012's `env.ts` (not yet landed at
# F3R5_004 time). Defaults are intentionally empty so the first apply
# doesn't hard-fail on unset values. Real environments MUST override these
# via tfvars before the admin UI is traffic-bearing.
# ---------------------------------------------------------------------------

variable "region_binding_validator_url" {
  description = <<-EOT
    Base URL of the region binding validator service that the admin UI calls
    S2S to validate `org_region_bindings` before accepting a domain.
    Matches `REGION_BINDING_VALIDATOR_URL` in F3R5_012's env schema.
  EOT
  type        = string
  default     = ""
}

variable "region_binding_validator_s2s_secret" {
  description = <<-EOT
    Shared S2S secret between the admin UI and the region binding validator.
    Matches `REGION_BINDING_VALIDATOR_S2S_SECRET` in F3R5_012. Treated as
    sensitive. Wire this via a future Secret Manager mount rather than
    passing it in cleartext once F3R5_012 lands.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "admin_ui_sso_issuer_url" {
  description = <<-EOT
    OIDC issuer URL the admin UI uses for SSO (matches what apps/me uses in
    the f3-nation monorepo). Defaults to empty so first apply doesn't fail;
    real environments MUST override.
  EOT
  type        = string
  default     = ""
}

variable "admin_ui_sso_client_id" {
  description = "OIDC client ID for the admin UI SSO integration. Matches apps/me convention."
  type        = string
  default     = ""
}
