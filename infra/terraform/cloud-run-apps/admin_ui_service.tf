# Redirect admin UI Cloud Run service — Decision 5 of the R5 plan.
#
# The admin UI is the operator console for platform super-admins. It is
# user-facing (SSO at the app layer) and NOT routed through the tenant
# cert map — it lives under its own `redirect-admin.f3nation.com` style
# hostname with an out-of-band cert. That hostname's cert map entry is
# managed out of scope for F3R5_004.
#
# Cold starts are acceptable for an operator console, so `min_instance_count`
# is zero. The service sizes larger than the runtime (1 GiB memory) because
# Next.js SSR + hydration is heavier than the runtime's hot-path read loop.

resource "google_cloud_run_v2_service" "admin_ui" {
  name     = "redirect-admin"
  location = var.admin_ui_region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.admin_ui_service_account_email

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    timeout = "300s"

    containers {
      image = local.admin_ui_image

      ports {
        container_port = 3000 # Next.js default
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # Neon admin UI connection string — scoped to the admin UI Postgres
      # role, which has SELECT on everything and INSERT/UPDATE only on the
      # admin write tables (see Decision 8).
      env {
        name = "REDIRECT_PLATFORM_DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = var.neon_redirect_admin_ui_secret_name
            version = "latest"
          }
        }
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "REDIRECT_CERT_MAP_NAME"
        value = var.cert_map_name
      }

      env {
        name  = "REDIRECT_LB_IPV4"
        value = var.lb_ipv4_address
      }

      # F3R5_012 env schema — `REGION_BINDING_VALIDATOR_URL` + its S2S
      # secret. Defaults are empty; real environments MUST override via
      # tfvars. Once F3R5_012 lands, move the S2S secret to Secret Manager
      # and mount it via `value_source.secret_key_ref` instead of passing
      # it as cleartext.
      # TODO(F3R5_012): wire S2S secret through Secret Manager.
      env {
        name  = "REGION_BINDING_VALIDATOR_URL"
        value = var.region_binding_validator_url
      }

      env {
        name  = "REGION_BINDING_VALIDATOR_S2S_SECRET"
        value = var.region_binding_validator_s2s_secret
      }

      # SSO env vars — match apps/me conventions in the f3-nation monorepo.
      # TODO(F3R5_012): confirm exact env var names against apps/me once the
      # admin UI package lands; these may need renaming.
      env {
        name  = "ADMIN_UI_SSO_ISSUER_URL"
        value = var.admin_ui_sso_issuer_url
      }

      env {
        name  = "ADMIN_UI_SSO_CLIENT_ID"
        value = var.admin_ui_sso_client_id
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# ---------------------------------------------------------------------------
# IAM — public access. SSO auth happens at the app layer, not at Cloud Run.
# ---------------------------------------------------------------------------

resource "google_cloud_run_v2_service_iam_member" "admin_ui_invoker_public" {
  project  = google_cloud_run_v2_service.admin_ui.project
  location = google_cloud_run_v2_service.admin_ui.location
  name     = google_cloud_run_v2_service.admin_ui.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
