provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  service_environment_variables = {
    REGION_SLUG = var.region_slug
    REGION_ID   = var.region_id
    REGION_NAME = var.region_name
  }

  web_service_account_id   = replace(substr("${var.web_service_name}-sa", 0, 30), "-", "")
  stats_service_account_id = replace(substr("${var.stats_service_name}-sa", 0, 30), "-", "")
}

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "containers" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repository_id
  description   = "Container images for the F3 region redirect services."
  format        = "DOCKER"
  labels        = var.service_labels

  depends_on = [google_project_service.required]
}

resource "google_service_account" "web" {
  project      = var.project_id
  account_id   = local.web_service_account_id
  display_name = "F3 region web redirect runtime"
}

resource "google_service_account" "stats" {
  project      = var.project_id
  account_id   = local.stats_service_account_id
  display_name = "F3 region stats redirect runtime"
}

resource "google_cloud_run_v2_service" "web" {
  name     = var.web_service_name
  location = var.region
  ingress  = var.ingress
  labels   = var.service_labels

  template {
    service_account = google_service_account.web.email

    scaling {
      min_instance_count = var.web_min_instance_count
      max_instance_count = var.web_max_instance_count
    }

    containers {
      image = var.web_image

      ports {
        container_port = 8080
      }

      dynamic "env" {
        for_each = local.service_environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_cloud_run_v2_service" "stats" {
  name     = var.stats_service_name
  location = var.region
  ingress  = var.ingress
  labels   = var.service_labels

  template {
    service_account = google_service_account.stats.email

    scaling {
      min_instance_count = var.stats_min_instance_count
      max_instance_count = var.stats_max_instance_count
    }

    containers {
      image = var.stats_image

      ports {
        container_port = 8080
      }

      dynamic "env" {
        for_each = local.service_environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_cloud_run_v2_service_iam_member" "web_invoker" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = google_cloud_run_v2_service.web.location
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "stats_invoker" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = google_cloud_run_v2_service.stats.location
  name     = google_cloud_run_v2_service.stats.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_domain_mapping" "web" {
  count    = var.web_domain == "" ? 0 : 1
  name     = var.web_domain
  location = google_cloud_run_v2_service.web.location

  metadata {
    namespace = data.google_project.current.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.web.name
  }
}

resource "google_cloud_run_domain_mapping" "stats" {
  count    = var.stats_domain == "" ? 0 : 1
  name     = var.stats_domain
  location = google_cloud_run_v2_service.stats.location

  metadata {
    namespace = data.google_project.current.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.stats.name
  }
}
