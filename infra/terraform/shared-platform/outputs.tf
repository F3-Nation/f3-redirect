output "lb_ipv4_address" {
  description = "Static IPv4 address of the R5 redirect platform LB. Region admins point A records here."
  value       = google_compute_global_address.redirect_lb_ipv4.address
}

output "lb_ipv6_address" {
  description = "Static IPv6 address of the R5 redirect platform LB. Region admins point AAAA records here."
  value       = google_compute_global_address.redirect_lb_ipv6.address
}

output "cert_map_name" {
  description = "Short name of the shared CertificateMap (tenant entries managed at runtime by the reconciler)."
  value       = google_certificate_manager_certificate_map.redirect_cert_map.name
}

output "cert_map_resource_id" {
  description = "Fully-qualified resource ID of the CertificateMap, usable by other modules that need to attach to it."
  value       = google_certificate_manager_certificate_map.redirect_cert_map.id
}

output "backend_service_self_link" {
  description = "Self-link of the placeholder backend service. F3R5_004 attaches the Cloud Run runtime NEG here."
  value       = google_compute_backend_service.redirect_default.self_link
}

output "runtime_service_account_email" {
  description = "Email of the redirect-runtime service account (Decision 3, runtime Cloud Run service)."
  value       = google_service_account.runtime.email
}

output "reconciler_service_account_email" {
  description = "Email of the redirect-reconciler service account (Decision 6, reconciler Cloud Run job)."
  value       = google_service_account.reconciler.email
}

output "admin_ui_service_account_email" {
  description = "Email of the redirect-admin-ui service account (Decision 5, admin UI in the f3-nation monorepo)."
  value       = google_service_account.admin_ui.email
}
