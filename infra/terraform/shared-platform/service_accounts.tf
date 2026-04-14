# Service accounts for the three R5 redirect platform workloads.
# IAM scoping per Decision 8 of the R5 plan. The important thing in each
# block is what is NOT granted — the comments document the intentional
# omissions so future edits don't accidentally widen the blast radius.

# ---------------------------------------------------------------------------
# redirect-runtime
# Runtime reads from Neon via Secret Manager only. No Cert Manager, no Compute,
# no Pub/Sub, no Cloud SQL.
# ---------------------------------------------------------------------------

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "redirect-runtime"
  display_name = "Redirect Platform Runtime"
  description  = "Used by the multi-tenant redirect Cloud Run runtime service (Decision 3)."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "runtime_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

# ---------------------------------------------------------------------------
# redirect-reconciler
# Reconciler has mutation rights on Cert Manager + LB. No uptime check roles
# (R5 uses SNI probe, not Cloud Monitoring uptime checks).
# ---------------------------------------------------------------------------

resource "google_service_account" "reconciler" {
  project      = var.project_id
  account_id   = "redirect-reconciler"
  display_name = "Redirect Platform Reconciler"
  description  = "Used by the reconciler Cloud Run job in us-central1 and europe-west1 (Decision 6)."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "reconciler_cert_editor" {
  project = var.project_id
  role    = "roles/certificatemanager.editor"
  member  = "serviceAccount:${google_service_account.reconciler.email}"
}

resource "google_project_iam_member" "reconciler_lb_admin" {
  project = var.project_id
  role    = "roles/compute.loadBalancerAdmin"
  member  = "serviceAccount:${google_service_account.reconciler.email}"
}

resource "google_project_iam_member" "reconciler_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.reconciler.email}"
}

# ---------------------------------------------------------------------------
# redirect-admin-ui
# Admin UI is read-only on GCP. All mutations go through the reconciler.
# ---------------------------------------------------------------------------

resource "google_service_account" "admin_ui" {
  project      = var.project_id
  account_id   = "redirect-admin-ui"
  display_name = "Redirect Platform Admin UI"
  description  = "Used by the apps/redirect-admin Cloud Run service in the f3-nation monorepo (Decision 5)."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "admin_ui_cert_viewer" {
  project = var.project_id
  role    = "roles/certificatemanager.viewer"
  member  = "serviceAccount:${google_service_account.admin_ui.email}"
}

resource "google_project_iam_member" "admin_ui_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.admin_ui.email}"
}

# ---------------------------------------------------------------------------
# Secret Manager IAM — one binding per (service account, secret) pair.
#
# Each Cloud Run service account can read ONLY its own Neon connection string.
# Bindings are scoped to the individual secret resource (not the project) so
# that the blast radius of a leaked runtime token is exactly one DB role.
# See Decision 8 "Layer 1 — Secret Manager + Neon connection strings".
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret_iam_member" "runtime_neon_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.neon_redirect["runtime"].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "reconciler_neon_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.neon_redirect["reconciler"].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.reconciler.email}"
}

resource "google_secret_manager_secret_iam_member" "admin_ui_neon_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.neon_redirect["admin_ui"].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.admin_ui.email}"
}

# neon-redirect-platform-admin-url is intentionally NOT bound to any Cloud Run
# service account. It holds the privileged migration role used by the CI job
# that runs Drizzle migrations against the f3-redirect-platform Neon project
# (Decision 8). Access for that CI job is granted out-of-band once the job
# identity exists; binding it here would couple this module to CI wiring that
# does not yet live in Terraform.
