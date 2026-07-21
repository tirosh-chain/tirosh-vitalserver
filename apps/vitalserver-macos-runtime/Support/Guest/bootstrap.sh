#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="tirosh"
MOUNT_POINT="/mnt/tirosh"
DEPLOY_DIR="${MOUNT_POINT}/deploy"
GUEST_TOOLS_HOME="/opt/tirosh/guest-tools"
GUEST_TOOLS_VENV="${GUEST_TOOLS_HOME}/venv"
PYTHON_WHEEL_DIR="${DEPLOY_DIR}/python-wheels"

if [ "$(id -u)" -ne 0 ]; then
  printf "error: run with sudo\n" >&2
  exit 1
fi

mount_share() {
  local tag="$1"
  local mount_point="$2"

  mkdir -p "${mount_point}"
  if ! mountpoint -q "${mount_point}"; then
    mount -t virtiofs "${tag}" "${mount_point}"
  fi
}

install_guest_tools_runtime() {
  python3 "${DEPLOY_DIR}/install-guest-tools-runtime.py" \
    --wheel-dir "${PYTHON_WHEEL_DIR}" \
    --guest-tools-home "${GUEST_TOOLS_HOME}"
  "${GUEST_TOOLS_VENV}/bin/tirosh-guest-tools-install-config"
}

mount_share "${MOUNT_TAG}" "${MOUNT_POINT}"
python3 "${DEPLOY_DIR}/pre_bootstrap_quiesce.py"
install_guest_tools_runtime
exec "${GUEST_TOOLS_VENV}/bin/tirosh-vitalserver-bootstrap"
