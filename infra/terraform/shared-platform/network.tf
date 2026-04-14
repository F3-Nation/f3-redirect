# Global external HTTPS LB shell for the R5 redirect platform (Decision 2).
#
# This file provisions the network plumbing only:
#   - static IPv4 + IPv6 global addresses
#   - an empty backend service (no backends attached)
#   - URL map that routes everything to the placeholder backend
#   - target HTTPS proxy attached to the cert map from cert_manager.tf
#   - forwarding rules bound to the static IPs
#
# Backends are wired by F3R5_004 (Cloud Run runtime NEG). This module creates
# the shell only.

# ---------------------------------------------------------------------------
# Static IPs. Never change. Region admins point A/AAAA records at these.
# ---------------------------------------------------------------------------

resource "google_compute_global_address" "redirect_lb_ipv4" {
  name         = "redirect-lb-ipv4"
  project      = var.project_id
  description  = "Static IPv4 for the R5 redirect platform global HTTPS LB."
  address_type = "EXTERNAL"
  ip_version   = "IPV4"

  depends_on = [google_project_service.required]
}

resource "google_compute_global_address" "redirect_lb_ipv6" {
  name         = "redirect-lb-ipv6"
  project      = var.project_id
  description  = "Static IPv6 for the R5 redirect platform global HTTPS LB."
  address_type = "EXTERNAL"
  ip_version   = "IPV6"

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Backend service — placeholder with no backends attached.
# Backends wired by F3R5_004 (Cloud Run runtime NEG). This module creates the
# shell only.
# ---------------------------------------------------------------------------

resource "google_compute_backend_service" "redirect_default" {
  name                  = "redirect-default-backend"
  project               = var.project_id
  description           = "Placeholder backend service for the R5 redirect LB. Backends attached by F3R5_004."
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_name             = "http"
  timeout_sec           = 30

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # Intentionally no `backend {}` blocks. F3R5_004 adds the Cloud Run NEG.

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# URL map — routes everything to the placeholder backend.
# ---------------------------------------------------------------------------

resource "google_compute_url_map" "redirect_lb" {
  name            = "redirect-lb-url-map"
  project         = var.project_id
  description     = "URL map for the R5 redirect platform global HTTPS LB."
  default_service = google_compute_backend_service.redirect_default.self_link
}

# ---------------------------------------------------------------------------
# Target HTTPS proxy — attaches the cert map from cert_manager.tf.
#
# The `certificate_map` argument requires the google-beta provider and takes
# the resource URL form:
#   //certificatemanager.googleapis.com/projects/<project>/locations/global/certificateMaps/<name>
# ---------------------------------------------------------------------------

resource "google_compute_target_https_proxy" "redirect_lb" {
  provider = google-beta

  name    = "redirect-lb-https-proxy"
  project = var.project_id
  url_map = google_compute_url_map.redirect_lb.self_link

  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.redirect_cert_map.id}"
}

# ---------------------------------------------------------------------------
# Forwarding rules — one per address family. Both target the same proxy.
# ---------------------------------------------------------------------------

resource "google_compute_global_forwarding_rule" "redirect_lb_ipv4" {
  name                  = "redirect-lb-ipv4-fr"
  project               = var.project_id
  ip_protocol           = "TCP"
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.redirect_lb_ipv4.address
  target                = google_compute_target_https_proxy.redirect_lb.self_link
}

resource "google_compute_global_forwarding_rule" "redirect_lb_ipv6" {
  name                  = "redirect-lb-ipv6-fr"
  project               = var.project_id
  ip_protocol           = "TCP"
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.redirect_lb_ipv6.address
  target                = google_compute_target_https_proxy.redirect_lb.self_link
}
