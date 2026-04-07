output "artifact_registry_repository_name" {
  description = "Artifact Registry repository name."
  value       = google_artifact_registry_repository.containers.name
}

output "artifact_registry_repository_url" {
  description = "Artifact Registry hostname/repository path prefix for docker pushes."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}"
}

output "web_service_url" {
  description = "Cloud Run URL for the main region redirect app."
  value       = google_cloud_run_v2_service.web.uri
}

output "stats_service_url" {
  description = "Cloud Run URL for the stats redirect app."
  value       = google_cloud_run_v2_service.stats.uri
}

output "web_service_account_email" {
  description = "Runtime service account email for the web service."
  value       = google_service_account.web.email
}

output "stats_service_account_email" {
  description = "Runtime service account email for the stats service."
  value       = google_service_account.stats.email
}

output "web_domain_mapping_records" {
  description = "DNS records returned by Google for the web domain mapping. Copy these into GoDaddy or your DNS provider."
  value       = try(google_cloud_run_domain_mapping.web[0].status[0].resource_records, [])
}

output "stats_domain_mapping_records" {
  description = "DNS records returned by Google for the stats domain mapping. Copy these into GoDaddy or your DNS provider."
  value       = try(google_cloud_run_domain_mapping.stats[0].status[0].resource_records, [])
}
