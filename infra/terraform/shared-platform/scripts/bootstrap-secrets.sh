#!/usr/bin/env bash
#
# bootstrap-secrets.sh
#
# One-time (or post-rotation) helper that writes the four Neon connection
# strings as versions of the Secret Manager secrets created by the
# shared-platform Terraform module. Terraform never sees the raw passwords;
# this script is the manual path that keeps them out of state.
#
# Secrets written:
#   - neon-redirect-runtime-url
#   - neon-redirect-reconciler-url
#   - neon-redirect-admin-ui-url
#   - neon-redirect-platform-admin-url
#
# Idempotency guard: refuses to run if ANY of the four secrets already has
# a version >= 1. Pass --force to override (use when rotating).
#
# Values come from one of:
#   1. Environment variables NEON_RUNTIME_URL, NEON_RECONCILER_URL,
#      NEON_ADMIN_UI_URL, NEON_PLATFORM_ADMIN_URL
#   2. Four positional arguments in the same order
#
# Values are NEVER echoed, logged, or written to disk.

set -euo pipefail

readonly PROJECT_ID="f3-redirects"

readonly SECRET_RUNTIME="neon-redirect-runtime-url"
readonly SECRET_RECONCILER="neon-redirect-reconciler-url"
readonly SECRET_ADMIN_UI="neon-redirect-admin-ui-url"
readonly SECRET_PLATFORM_ADMIN="neon-redirect-platform-admin-url"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-secrets.sh [--force] [-h|--help]
  bootstrap-secrets.sh [--force] <runtime_url> <reconciler_url> <admin_ui_url> <platform_admin_url>

Writes the four Neon connection strings as new versions of their Secret
Manager secrets in the f3-redirects GCP project.

Input (pick one):
  Env vars: NEON_RUNTIME_URL, NEON_RECONCILER_URL, NEON_ADMIN_UI_URL,
            NEON_PLATFORM_ADMIN_URL
  Args:     four positional arguments in the same order

Each value must start with "postgresql://" and contain "sslmode=require".

Flags:
  --force     Write a new version even if any secret already has versions.
  -h, --help  Show this message.

Exits non-zero with a clear message on any validation or gcloud failure.
Never echoes secret values to stdout, stderr, or logs.
EOF
}

die() {
  echo "bootstrap-secrets: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found on PATH"
}

validate_url() {
  # $1 = human-readable label, $2 = value (treated as opaque)
  local label="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    die "${label}: empty connection string"
  fi
  if [[ "${value}" != postgresql://* ]]; then
    die "${label}: must start with 'postgresql://'"
  fi
  if [[ "${value}" != *"sslmode=require"* ]]; then
    die "${label}: must include 'sslmode=require'"
  fi
}

secret_has_versions() {
  # Returns 0 (true) if the secret already has at least one enabled version.
  local name="$1"
  local count
  count=$(
    gcloud secrets versions list "${name}" \
      --project="${PROJECT_ID}" \
      --format="value(name)" \
      --filter="state=ENABLED" 2>/dev/null | wc -l | tr -d '[:space:]'
  )
  [[ "${count}" != "0" ]]
}

add_version() {
  # Adds a new version to the given secret from stdin. Prints only the
  # returned version resource short id — never the payload.
  local name="$1"
  local value="$2"
  local version_id
  if ! version_id=$(
    printf '%s' "${value}" \
      | gcloud secrets versions add "${name}" \
          --project="${PROJECT_ID}" \
          --data-file=- \
          --format="value(name)" 2>/dev/null
  ); then
    die "failed to add version to secret '${name}' (check gcloud auth and project permissions)"
  fi
  # name field is like "projects/<num>/secrets/<id>/versions/<n>" — extract <n>.
  local version_number="${version_id##*/}"
  echo "  ${name}: wrote version ${version_number}"
}

main() {
  local force=0
  local -a positional=()

  while (($# > 0)); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --force)
        force=1
        shift
        ;;
      --)
        shift
        while (($# > 0)); do
          positional+=("$1")
          shift
        done
        ;;
      -*)
        die "unknown flag: $1 (try --help)"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  require_cmd gcloud

  local runtime_url reconciler_url admin_ui_url platform_admin_url

  if ((${#positional[@]} == 4)); then
    runtime_url="${positional[0]}"
    reconciler_url="${positional[1]}"
    admin_ui_url="${positional[2]}"
    platform_admin_url="${positional[3]}"
  elif ((${#positional[@]} == 0)); then
    runtime_url="${NEON_RUNTIME_URL:-}"
    reconciler_url="${NEON_RECONCILER_URL:-}"
    admin_ui_url="${NEON_ADMIN_UI_URL:-}"
    platform_admin_url="${NEON_PLATFORM_ADMIN_URL:-}"
    if [[ -z "${runtime_url}" || -z "${reconciler_url}" || -z "${admin_ui_url}" || -z "${platform_admin_url}" ]]; then
      die "missing input. Set NEON_RUNTIME_URL, NEON_RECONCILER_URL, NEON_ADMIN_UI_URL, NEON_PLATFORM_ADMIN_URL or pass 4 positional args. Run with --help for details."
    fi
  else
    die "expected either 0 or 4 positional args, got ${#positional[@]}. Run with --help."
  fi

  validate_url "NEON_RUNTIME_URL" "${runtime_url}"
  validate_url "NEON_RECONCILER_URL" "${reconciler_url}"
  validate_url "NEON_ADMIN_UI_URL" "${admin_ui_url}"
  validate_url "NEON_PLATFORM_ADMIN_URL" "${platform_admin_url}"

  if ((force == 0)); then
    local existing=()
    for secret in "${SECRET_RUNTIME}" "${SECRET_RECONCILER}" "${SECRET_ADMIN_UI}" "${SECRET_PLATFORM_ADMIN}"; do
      if secret_has_versions "${secret}"; then
        existing+=("${secret}")
      fi
    done
    if ((${#existing[@]} > 0)); then
      echo "bootstrap-secrets: the following secrets already have enabled versions:" >&2
      for s in "${existing[@]}"; do
        echo "  - ${s}" >&2
      done
      die "refusing to overwrite. Re-run with --force if you are intentionally rotating."
    fi
  fi

  echo "Writing Neon connection strings to Secret Manager in project '${PROJECT_ID}':"
  add_version "${SECRET_RUNTIME}" "${runtime_url}"
  add_version "${SECRET_RECONCILER}" "${reconciler_url}"
  add_version "${SECRET_ADMIN_UI}" "${admin_ui_url}"
  add_version "${SECRET_PLATFORM_ADMIN}" "${platform_admin_url}"
  echo "Done."
}

main "$@"
