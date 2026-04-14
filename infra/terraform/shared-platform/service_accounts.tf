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
