# Redirect runtime Cloud Run service — Decision 3 of the R5 plan.
#
# The runtime serves the entire read-path for every tenant redirect. It sits
# behind the shared external HTTPS LB, so ingress is scoped to LB + internal
# traffic only (no direct public hostname). `min_instance_count = 1` keeps
# one warm instance to avoid cold-start cache load penalty on the first
# request after a quiet window — explicitly called out in Decision 3.

resource "google_cloud_run_v2_service" "runtime" {
  name     = "redirect-runtime"
  location = var.runtime_region
  project  = var.project_id

  # Only the LB and internal callers can hit the service directly. Public
  # traffic flows LB → serverless NEG → this service. The provider accepts
  # `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` for this mode (which GCP's UI
  # renders as "Internal + Cloud Load Balancing").
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = var.runtime_service_account_email

    scaling {
      min_instance_count = 1  # Decision 3 — warm instance avoids cold cache
      max_instance_count = 10 # conservative upper bound; revisit with traffic data
    }

    timeout = "60s"

    containers {
      image = local.runtime_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # Neon connection string mounted from Secret Manager. The runtime
      # service account has `secretAccessor` scoped to THIS secret only
      # (see shared-platform/service_accounts.tf "runtime_neon_accessor").
      env {
        name = "REDIRECT_PLATFORM_DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = var.neon_redirect_runtime_secret_name
            version = "latest"
          }
        }
      }

      # Fallback redirect target when a hostname has no `active` row. Kept
      # deliberately narrow — anything smarter is a runtime concern.
      env {
        name  = "RUNTIME_FALLBACK_REDIRECT_URL"
        value = "https://redirect.f3nation.com/not-provisioned"
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "RUNTIME_REGION"
        value = var.runtime_region
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  # Cloud Run v2 reports the spec drift for any field Terraform doesn't
  # explicitly set. These are the fields GCP sets itself on create/update
  # that we intentionally ignore to avoid churn on re-apply.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# ---------------------------------------------------------------------------
# IAM — allow invocation via the LB.
#
# With `ingress = INGRESS_TRAFFIC_INTERNAL_AND_CLOUD_LOAD_BALANCING`, the LB
# is the only public path. The v2 service still requires an explicit
# `roles/run.invoker` binding to accept requests. Granting `allUsers` the
# invoker role here is safe because the ingress setting enforces the
# LB-only reachability at the network layer — allUsers binds the IAM policy
# for Cloud Run authz, but they can't reach the service directly.
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service_iam_member" "runtime_invoker_public" {
  project  = google_cloud_run_v2_service.runtime.project
  location = google_cloud_run_v2_service.runtime.location
  name     = google_cloud_run_v2_service.runtime.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
