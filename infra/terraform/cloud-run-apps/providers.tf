terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # Remote state lives in the same GCS bucket as `shared-platform`, under a
  # DIFFERENT prefix so that this module's state is isolated. Cloud Run
  # revisions churn every deploy — we never want an app apply to race with
  # or blast-radius-affect the LB / cert map state managed by shared-platform.
  backend "gcs" {
    bucket = "f3-redirects-tfstate" # override at init time with -backend-config=bucket=...
    prefix = "terraform/state/cloud-run-apps"
  }
}

provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}
