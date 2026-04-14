# Enable every GCP API the R5 redirect platform needs. Keep disable_on_destroy
# = false so destroying this module never yanks APIs out from under other
# workloads in the same project (e.g. cloud-run/ legacy module, ad-hoc tooling).

locals {
  required_services = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "certificatemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudscheduler.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
