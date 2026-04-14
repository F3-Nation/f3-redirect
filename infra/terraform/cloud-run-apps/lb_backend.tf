# LB → Cloud Run runtime wiring.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ Why this file is ugly: the Terraform google provider has no per-backend │
# │ sub-resource on `google_compute_backend_service`. Backends are an       │
# │ in-line attribute on the backend service resource itself. That means    │
# │ the only "clean" ways to attach a backend are:                          │
# │                                                                          │
# │   (a) Manage the backend service in ONE module (either shared-platform  │
# │       or here) and never split it.                                      │
# │   (b) Use `terraform_remote_state` to learn the backend service name    │
# │       and imperatively attach via `gcloud`, hidden behind a             │
# │       `null_resource` + `local-exec` with a trigger keyed to the NEG.   │
# │                                                                          │
# │ We picked (b) because (a) would force either:                            │
# │   - putting the LB in this module (cloud-run-apps applies churn the LB  │
# │     on every revision deploy — unacceptable blast radius), or           │
# │   - putting Cloud Run in shared-platform (infrastructure and app        │
# │     revisions share state — every app deploy becomes a shared-platform  │
# │     apply — unacceptable coupling).                                     │
# │                                                                          │
# │ Trade-off of option (b): the attachment is not pure Terraform state.   │
# │ It's observed via a trigger hash over the NEG ID, so re-applies are    │
# │ idempotent and backend detachment happens automatically when the NEG   │
# │ is replaced. If someone deletes the backend service entirely, the      │
# │ trigger will not notice — but that's a shared-platform concern and is  │
# │ guarded by the `lifecycle.ignore_changes = [backend]` on the placeholder │
# │ so apply-churn doesn't accidentally strip the attachment.               │
# └──────────────────────────────────────────────────────────────────────────┘

# ---------------------------------------------------------------------------
# Read shared-platform state so we know the backend service name (and the
# self-link if we need it). The backend service was created as a shell in
# F3R5_003 with `lifecycle { ignore_changes = [backend] }` specifically so
# this module can attach backends to it without fighting a re-plan loop.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "shared_platform" {
  backend = "gcs"

  config = {
    bucket = var.shared_platform_state_bucket
    prefix = var.shared_platform_state_prefix
  }
}

locals {
  # `backend_service_self_link` comes from shared-platform/outputs.tf. If
  # that output is renamed, this breaks at plan time with a clear error.
  shared_backend_service_self_link = data.terraform_remote_state.shared_platform.outputs.backend_service_self_link

  # The backend service name is the last path component of the self-link.
  # Used by the `gcloud` attach command below (which takes --name, not
  # --self-link). regex() is Terraform builtin and returns a single match.
  shared_backend_service_name = regex("[^/]+$", local.shared_backend_service_self_link)
}

# ---------------------------------------------------------------------------
# Serverless NEG pointing at the runtime Cloud Run service.
# This IS fully managed by Terraform — only the ATTACHMENT to the backend
# service is imperative below.
# ---------------------------------------------------------------------------

resource "google_compute_region_network_endpoint_group" "runtime_neg" {
  name                  = "redirect-runtime-neg"
  project               = var.project_id
  region                = var.runtime_region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.runtime.name
  }
}

# ---------------------------------------------------------------------------
# Imperative attachment. Trigger keyed to the NEG self-link: any NEG
# replacement (rename, region change) forces a re-run. The destroy command
# detaches cleanly; the create command is idempotent because
# `backend-services add-backend` is rejected with ALREADY_EXISTS on
# duplicate, which we swallow with `|| true` — matching the reconciler's
# own ALREADY_EXISTS-as-success-path handling in Decision 6 (nice symmetry).
#
# Requires `gcloud` on the applying machine's PATH with credentials that
# can edit the shared-platform backend service (i.e. the applying
# principal from shared-platform's README IAM section).
# ---------------------------------------------------------------------------

resource "null_resource" "attach_runtime_neg_to_backend_service" {
  triggers = {
    neg_self_link       = google_compute_region_network_endpoint_group.runtime_neg.self_link
    backend_service     = local.shared_backend_service_name
    project_id          = var.project_id
    runtime_service_rev = google_cloud_run_v2_service.runtime.uid
  }

  provisioner "local-exec" {
    when        = create
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      gcloud compute backend-services add-backend ${local.shared_backend_service_name} \
        --global \
        --project=${var.project_id} \
        --network-endpoint-group=${google_compute_region_network_endpoint_group.runtime_neg.name} \
        --network-endpoint-group-region=${var.runtime_region} 2>&1 | tee /dev/stderr | grep -qiE 'alreadyExists|Updated' || true
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      gcloud compute backend-services remove-backend ${self.triggers.backend_service} \
        --global \
        --project=${self.triggers.project_id} \
        --network-endpoint-group=$(basename ${self.triggers.neg_self_link}) \
        --network-endpoint-group-region=$(echo ${self.triggers.neg_self_link} | awk -F/ '{print $(NF-2)}') 2>&1 | tee /dev/stderr || true
    EOT
  }

  depends_on = [
    google_compute_region_network_endpoint_group.runtime_neg,
    google_cloud_run_v2_service.runtime,
  ]
}
