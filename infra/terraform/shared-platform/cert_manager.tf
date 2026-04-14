# Certificate Manager cert map for tenant certs.
#
# This module creates the empty CertificateMap resource only. Map entries
# (one per tenant hostname) are added at runtime by the reconciler per
# Decision 6 — Terraform does not know about tenants.
#
# The map is attached to the target HTTPS proxy in network.tf via the
# google-beta provider's `certificate_map` argument on
# google_compute_target_https_proxy.

resource "google_certificate_manager_certificate_map" "redirect_cert_map" {
  provider = google-beta

  name        = "redirect-platform-cert-map"
  description = "Tenant cert map for the R5 redirect platform. Entries are managed by the reconciler at runtime."
  project     = var.project_id

  labels = {
    managed_by = "terraform"
    module     = "shared-platform"
    component  = "cert-map"
  }

  depends_on = [google_project_service.required]
}
