# Secret Manager secrets for the four Neon connection strings used by the
# R5 redirect platform. See Decision 8 of the R5 plan for the per-secret
# role mapping.
#
# IMPORTANT: these secrets are intentionally created EMPTY. Terraform never
# sees the raw Neon passwords. The first version of each secret is written
# out-of-band by `scripts/bootstrap-secrets.sh` (see README "Secret bootstrap"
# section). Subsequent rotations also go through the script or a CI job, not
# through Terraform.

locals {
  neon_secrets = {
    runtime = {
      name = "neon-redirect-runtime-url"
      role = "runtime"
    }
    reconciler = {
      name = "neon-redirect-reconciler-url"
      role = "reconciler"
    }
    admin_ui = {
      name = "neon-redirect-admin-ui-url"
      role = "admin-ui"
    }
    platform_admin = {
      name = "neon-redirect-platform-admin-url"
      role = "platform-admin"
    }
  }
}

resource "google_secret_manager_secret" "neon_redirect" {
  for_each = local.neon_secrets

  project   = var.project_id
  secret_id = each.value.name

  labels = {
    platform = "f3-redirect"
    role     = each.value.role
  }

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}
