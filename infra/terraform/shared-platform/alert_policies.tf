# Log-based metrics + alert policies for the three R5 platform labels.
#
# The reconciler writes structured Cloud Logging entries at severity CRITICAL
# with a label for each alert class:
#   - redirect_platform_drift           (Decision 6, halt-on-mismatch)
#   - redirect_platform_stuck_operation (Decision 6, 30-min heartbeat cap)
#   - redirect_platform_cert_renewal    (Decision 8, T-1 renewal ladder)
#
# Each label becomes a log-based counter metric; each counter metric gets an
# alert policy that fires when the metric increments above 0. Alerts notify
# PagerDuty + Slack via the two notification channels below.

# ---------------------------------------------------------------------------
# Notification channels
# ---------------------------------------------------------------------------

resource "google_monitoring_notification_channel" "pagerduty" {
  project      = var.project_id
  display_name = "PagerDuty (redirect platform)"
  type         = "webhook_tokenauth"
  description  = "PagerDuty Events API v2 webhook for the R5 redirect platform."

  sensitive_labels {
    auth_token = var.pagerduty_webhook_url
  }

  labels = {
    url = var.pagerduty_webhook_url
  }

  depends_on = [google_project_service.required]
}

resource "google_monitoring_notification_channel" "slack" {
  project      = var.project_id
  display_name = "#f3-platform-alerts (Slack incoming webhook)"
  # webhook_tokenauth is used here instead of the native `slack` type because
  # the native type requires an OAuth-installed Slack app in the Monitoring
  # workspace — we only have an incoming-webhook URL. webhook_tokenauth posts
  # the same payload shape Slack's incoming webhook accepts.
  type        = "webhook_tokenauth"
  description = "Slack incoming webhook for #f3-platform-alerts."

  sensitive_labels {
    auth_token = var.slack_webhook_url
  }

  labels = {
    url = var.slack_webhook_url
  }

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Log-based metrics
# ---------------------------------------------------------------------------

# Drift: the reconciler halts on spec_mismatch / orphan_resource /
# unexpected_state (Decision 6). Label set on the CRITICAL log entry.
# TODO: validate filter syntax on first apply; plan preview needed before
# production cutover. The filter syntax for structured payload labels may
# need tightening depending on how the reconciler emits the entry
# (jsonPayload.labels vs labels vs textPayload).
resource "google_logging_metric" "redirect_platform_drift" {
  project = var.project_id
  name    = "redirect_platform_drift"

  description = "Count of reconciler drift CRITICAL log entries. See docs/runbooks/reconciler-drift.md."

  filter = <<-EOT
    resource.type="cloud_run_job"
    severity=CRITICAL
    jsonPayload.labels.redirect_platform_drift="true"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }

  depends_on = [google_project_service.required]
}

# Stuck operation: the reconciler hit the 30-min heartbeat cap on a single
# operation (Decision 6, lease heartbeat section).
# TODO: validate filter syntax on first apply.
resource "google_logging_metric" "redirect_platform_stuck_operation" {
  project = var.project_id
  name    = "redirect_platform_stuck_operation"

  description = "Count of reconciler stuck-operation CRITICAL log entries. See docs/runbooks/stuck-operation.md."

  filter = <<-EOT
    resource.type="cloud_run_job"
    severity=CRITICAL
    jsonPayload.labels.redirect_platform_stuck_operation="true"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }

  depends_on = [google_project_service.required]
}

# Cert renewal: T-1 escalation in the renewal ladder (Decision 8).
# TODO: validate filter syntax on first apply.
resource "google_logging_metric" "redirect_platform_cert_renewal" {
  project = var.project_id
  name    = "redirect_platform_cert_renewal"

  description = "Count of reconciler cert-renewal CRITICAL log entries (T-1 ladder). See docs/runbooks/cert-renewal-failure.md."

  filter = <<-EOT
    resource.type="cloud_run_job"
    severity=CRITICAL
    jsonPayload.labels.redirect_platform_cert_renewal="true"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Alert policies — one per metric. Each sends to both channels. Combiner OR.
# ---------------------------------------------------------------------------

locals {
  notification_channels = [
    google_monitoring_notification_channel.pagerduty.id,
    google_monitoring_notification_channel.slack.id,
  ]
}

resource "google_monitoring_alert_policy" "redirect_platform_drift" {
  project      = var.project_id
  display_name = "Redirect platform: reconciler drift"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      Reconciler halted on drift for a domain in the R5 redirect platform.

      Runbook: ${var.runbook_base_url}/reconciler-drift.md

      Source: Decision 6 — GET-with-spec-check + halt-on-mismatch. Drift is
      treated as a bug requiring human investigation, not auto-repair.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Drift metric incremented"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.redirect_platform_drift.name}\" AND resource.type=\"cloud_run_job\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "604800s" # 7 days
  }
}

resource "google_monitoring_alert_policy" "redirect_platform_stuck_operation" {
  project      = var.project_id
  display_name = "Redirect platform: reconciler stuck operation"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      Reconciler hit the 30-minute heartbeat cap on a single operation in the
      R5 redirect platform.

      Runbook: ${var.runbook_base_url}/stuck-operation.md

      Source: Decision 6 — lease heartbeat hard cap.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Stuck-operation metric incremented"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.redirect_platform_stuck_operation.name}\" AND resource.type=\"cloud_run_job\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "604800s"
  }
}

resource "google_monitoring_alert_policy" "redirect_platform_cert_renewal" {
  project      = var.project_id
  display_name = "Redirect platform: cert renewal failure"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      T-1 cert renewal escalation fired for a domain in the R5 redirect
      platform. The cert will expire within 24 hours if not recovered.

      Runbook: ${var.runbook_base_url}/cert-renewal-failure.md

      Source: Decision 8 — T-14 / T-7 / T-1 renewal-failure ladder.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Cert-renewal metric incremented"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.redirect_platform_cert_renewal.name}\" AND resource.type=\"cloud_run_job\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "604800s"
  }
}
