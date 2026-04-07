#!/usr/bin/env bash
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_with_brew() {
  local pkg="$1"
  if need_cmd brew; then
    brew list "$pkg" >/dev/null 2>&1 || brew install "$pkg"
    return 0
  fi
  return 1
}

install_gcloud() {
  if need_cmd gcloud; then
    return 0
  fi

  if install_with_brew --cask google-cloud-sdk; then
    return 0
  fi

  if need_cmd apt-get; then
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y google-cloud-cli
    return 0
  fi

  echo "Unable to install gcloud automatically. Install Google Cloud CLI manually and re-run." >&2
  exit 1
}

install_terraform() {
  if need_cmd terraform; then
    return 0
  fi

  if install_with_brew terraform; then
    return 0
  fi

  if need_cmd apt-get; then
    sudo apt-get update
    sudo apt-get install -y gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y terraform
    return 0
  fi

  echo "Unable to install terraform automatically. Install Terraform manually and re-run." >&2
  exit 1
}

install_gcloud
install_terraform

echo "gcloud: $(command -v gcloud)"
echo "terraform: $(command -v terraform)"
