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
  }

  # Remote state lives in a GCS bucket in the f3-redirects project.
  # The bucket must be created out-of-band (see README). The prefix is
  # scoped to this module so it can coexist with other Terraform states
  # in the same bucket.
  backend "gcs" {
    bucket = "f3-redirects-tfstate" # replace or override via -backend-config on init
    prefix = "shared-platform"
  }
}

provider "google" {
  project = var.project_id
}

provider "google-beta" {
  project = var.project_id
}
