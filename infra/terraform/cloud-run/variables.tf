variable "project_id" {
  description = "Google Cloud project ID that will host the redirect services."
  type        = string
}

variable "region" {
  description = "Google Cloud region for Cloud Run and Artifact Registry."
  type        = string
  default     = "us-central1"
}

variable "artifact_registry_repository_id" {
  description = "Artifact Registry Docker repository that stores the web and stats images."
  type        = string
  default     = "f3-region-redirect"
}

variable "web_service_name" {
  description = "Cloud Run service name for the main region redirect app."
  type        = string
  default     = "f3-region-web"
}

variable "stats_service_name" {
  description = "Cloud Run service name for the stats redirect app."
  type        = string
  default     = "f3-region-stats"
}

variable "web_domain" {
  description = "Optional apex or subdomain mapped directly to the web Cloud Run service, for example f3muletown.com."
  type        = string
  default     = ""
}

variable "stats_domain" {
  description = "Optional domain mapped directly to the stats Cloud Run service, for example stats.f3muletown.com."
  type        = string
  default     = ""
}

variable "web_image" {
  description = "Fully-qualified container image for the web redirect service."
  type        = string
}

variable "stats_image" {
  description = "Fully-qualified container image for the stats redirect service."
  type        = string
}

variable "region_slug" {
  description = "Region slug on regions.f3nation.com, for example muletown."
  type        = string
}

variable "region_id" {
  description = "Numeric region ID used by pax-vault.f3nation.com/stats/region/<id>."
  type        = string
}

variable "region_name" {
  description = "Display name used in page metadata."
  type        = string
}

variable "ingress" {
  description = "Cloud Run ingress policy for both services."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
}

variable "allow_unauthenticated" {
  description = "Whether to make both redirect services publicly accessible."
  type        = bool
  default     = true
}

variable "web_min_instance_count" {
  description = "Minimum running instances for the web service."
  type        = number
  default     = 0
}

variable "web_max_instance_count" {
  description = "Maximum running instances for the web service."
  type        = number
  default     = 2
}

variable "stats_min_instance_count" {
  description = "Minimum running instances for the stats service."
  type        = number
  default     = 0
}

variable "stats_max_instance_count" {
  description = "Maximum running instances for the stats service."
  type        = number
  default     = 2
}

variable "service_labels" {
  description = "Labels applied to Artifact Registry and both Cloud Run services."
  type        = map(string)
  default = {
    application = "f3-region-redirect"
    managed_by  = "terraform"
  }
}
