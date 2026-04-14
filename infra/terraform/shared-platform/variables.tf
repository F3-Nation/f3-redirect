variable "project_id" {
  description = "GCP project hosting the shared redirect platform."
  type        = string
  default     = "f3-redirects"
}

variable "project_number" {
  description = "GCP project number for f3-redirects. Used by IAM bindings that require the numeric form."
  type        = string
  default     = "355149658273"
}

variable "regions" {
  description = <<-EOT
    Regions where the reconciler Cloud Run job runs (per Decision 4, multi-vantage
    SNI probe). This module does not create the Cloud Run job itself — that lives
    in F3R5_004 — but some resources reference the region list for labeling and
    documentation.
  EOT
  type        = list(string)
  default     = ["us-central1", "europe-west1"]
}

variable "pagerduty_webhook_url" {
  description = <<-EOT
    PagerDuty Events API v2 (or generic webhook) URL that Cloud Monitoring alert
    policies POST to. Provided via -var or a tfvars file on apply; never committed.
  EOT
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = <<-EOT
    Slack incoming webhook URL for #f3-platform-alerts. Provided via -var or a
    tfvars file on apply; never committed.
  EOT
  type        = string
  sensitive   = true
}

variable "runbook_base_url" {
  description = "Base URL where runbook markdown files are rendered for operators."
  type        = string
  default     = "https://github.com/F3-Nation/f3-redirect/blob/main/docs/runbooks"
}
