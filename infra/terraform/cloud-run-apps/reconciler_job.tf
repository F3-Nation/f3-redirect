# Redirect reconciler Cloud Run job — Decision 6 of the R5 plan.
#
# The reconciler is a Cloud Run **job** (not a service), invoked on a
# Cloud Scheduler cron every 5 minutes. It is deployed in TWO regions
# (`us-central1` and `europe-west1`) for SNI probe diversity (Decision 4).
# The singleton lease ensures only one region does reconciler work at a
# time in steady state — see the `reconciler_leases` table contract in the
# R5 plan.
#
# Timeout is 1800s (30 min) to match the lease heartbeat cap. Anything
# longer than that is a halt-and-alert bug per Decision 6.

resource "google_cloud_run_v2_job" "reconciler" {
  for_each = toset(var.regions)

  name     = "redirect-reconciler-${each.value}"
  location = each.value
  project  = var.project_id

  template {
    task_count  = 1
    parallelism = 1

    template {
      service_account = var.reconciler_service_account_email
      timeout         = "1800s" # Decision 6 — 30 min lease heartbeat cap
      max_retries     = 0       # crash-recovery scan handles retry logic

      containers {
        image = local.reconciler_image

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        # Neon connection string mounted from Secret Manager. Scoped to the
        # reconciler role only — see shared-platform/service_accounts.tf
        # "reconciler_neon_accessor".
        env {
          name = "REDIRECT_PLATFORM_DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = var.neon_redirect_reconciler_secret_name
              version = "latest"
            }
          }
        }

        env {
          name  = "RECONCILER_REGION"
          value = each.value
        }

        env {
          name  = "REDIRECT_LB_IPV4"
          value = var.lb_ipv4_address
        }

        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }

        env {
          name  = "REDIRECT_CERT_MAP_NAME"
          value = var.cert_map_name
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# ---------------------------------------------------------------------------
# Cloud Scheduler cron — every 5 minutes, per Decision 6.
#
# Uses the Cloud Run Admin API (`run.googleapis.com/v2`) to trigger a run
# of the job. The scheduler self-authenticates via the reconciler service
# account using an OAuth token; that SA has `roles/run.invoker` on itself
# via the IAM binding below, which is the Cloud Run Jobs invoker pattern.
# ---------------------------------------------------------------------------

resource "google_cloud_scheduler_job" "reconciler_cron" {
  for_each = toset(var.regions)

  name        = "redirect-reconciler-cron-${each.value}"
  region      = each.value
  project     = var.project_id
  description = "Triggers redirect-reconciler-${each.value} every 5 minutes (Decision 6)."
  schedule    = "*/5 * * * *"
  time_zone   = "UTC"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${each.value}-run.googleapis.com/v2/projects/${var.project_id}/locations/${each.value}/jobs/redirect-reconciler-${each.value}:run"

    oauth_token {
      service_account_email = var.reconciler_service_account_email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_cloud_run_v2_job.reconciler]
}

# The reconciler SA must be able to invoke its own Cloud Run jobs to run
# them on schedule. This is the canonical "Scheduler → Run Job" pattern.
resource "google_cloud_run_v2_job_iam_member" "reconciler_self_invoker" {
  for_each = toset(var.regions)

  project  = google_cloud_run_v2_job.reconciler[each.value].project
  location = google_cloud_run_v2_job.reconciler[each.value].location
  name     = google_cloud_run_v2_job.reconciler[each.value].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.reconciler_service_account_email}"
}
