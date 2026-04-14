output "runtime_service_name" {
  description = "Short name of the redirect-runtime Cloud Run service."
  value       = google_cloud_run_v2_service.runtime.name
}

output "runtime_service_url" {
  description = "Cloud Run URL of the redirect-runtime service (direct, not via the LB)."
  value       = google_cloud_run_v2_service.runtime.uri
}

output "runtime_neg_self_link" {
  description = "Self-link of the serverless NEG attached to the shared LB backend service."
  value       = google_compute_region_network_endpoint_group.runtime_neg.self_link
}

output "reconciler_job_names" {
  description = "Map of region → Cloud Run job name for the multi-region reconciler deploy."
  value       = { for region, job in google_cloud_run_v2_job.reconciler : region => job.name }
}

output "reconciler_scheduler_job_names" {
  description = "Map of region → Cloud Scheduler job name that triggers the reconciler cron."
  value       = { for region, cron in google_cloud_scheduler_job.reconciler_cron : region => cron.name }
}

output "admin_ui_service_name" {
  description = "Short name of the redirect-admin Cloud Run service."
  value       = google_cloud_run_v2_service.admin_ui.name
}

output "admin_ui_service_url" {
  description = "Cloud Run URL of the redirect-admin service. Used by operators before the custom hostname is wired."
  value       = google_cloud_run_v2_service.admin_ui.uri
}
