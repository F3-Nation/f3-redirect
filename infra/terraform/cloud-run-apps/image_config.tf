# Container image URIs for the three R5 workloads.
#
# TODO(F3R5_004): these images do not exist in Artifact Registry until the
# first CI/CD build-and-push. On first apply, Terraform will succeed at the
# API level (Cloud Run accepts any image reference string), but the Cloud
# Run revision will fail to start until real images are pushed under these
# tags. Build-and-push is a separate task and is not in scope for F3R5_004.
#
# The `:latest` tag is a placeholder. Production applies MUST override
# `*_image_tag` with a Git SHA or semver tag so deploys are pinned and
# rollbacks are deterministic.

locals {
  image_registry_host = "${var.artifact_registry_region}-docker.pkg.dev"
  image_repo_path     = "${local.image_registry_host}/${var.project_id}/${var.artifact_registry_repo}"

  runtime_image    = "${local.image_repo_path}/runtime:${var.runtime_image_tag}"
  reconciler_image = "${local.image_repo_path}/reconciler:${var.reconciler_image_tag}"
  admin_ui_image   = "${local.image_repo_path}/redirect-admin:${var.admin_ui_image_tag}"
}
