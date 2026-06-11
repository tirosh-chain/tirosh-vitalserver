#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="tirosh"
MOUNT_POINT="/mnt/tirosh"
VITAL_FILES_MOUNT_TAG="tirosh-vital-files"
VITAL_FILES_MOUNT_POINT="/mnt/tirosh-vital-files"
RUNTIME_DIR="${MOUNT_POINT}/run"
READY_FILE="${RUNTIME_DIR}/rootfs-ready"
RUNTIME_MANIFEST_FILE="${RUNTIME_DIR}/rootfs-runtime-manifest.json"
GUEST_TOOLS_HOME="/opt/tirosh/guest-tools"
GUEST_TOOLS_VENV="${GUEST_TOOLS_HOME}/venv"
PYTHON_WHEEL_DIR="${MOUNT_POINT}/deploy/python-wheels"

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

disable_flash_kernel_hook() {
  local hook="/etc/initramfs/post-update.d/flash-kernel"
  if [ -x "${hook}" ]; then
    chmod -x "${hook}"
  fi
}

remove_flash_kernel_package() {
  if dpkg-query -W flash-kernel >/dev/null 2>&1; then
    apt-get purge -y flash-kernel \
      || dpkg --purge --force-all flash-kernel \
      || true
  fi
}

repair_package_state() {
  if ! dpkg --configure -a; then
    apt-get -f install -y
  fi
}

install_runtime_packages() {
  export DEBIAN_FRONTEND=noninteractive

  timedatectl set-ntp true >/dev/null 2>&1 || true
  systemctl restart systemd-timesyncd >/dev/null 2>&1 || true
  disable_flash_kernel_hook
  remove_flash_kernel_package
  repair_package_state

  apt-get update
  apt-get install -y \
    avahi-daemon \
    busybox-static \
    ca-certificates \
    cloud-guest-utils \
    curl \
    docker.io \
    procps \
    psmisc \
    python3-minimal \
    python3-venv \
    util-linux

  if ! docker compose version >/dev/null 2>&1; then
    apt-get install -y docker-compose-v2 \
      || apt-get install -y docker-compose-plugin
  fi

  apt-get clean
  rm -rf /var/lib/apt/lists/*
}

verify_python_venv() {
  local test_venv

  test_venv="$(mktemp -d)"
  if ! python3 -m venv "${test_venv}" >/dev/null 2>&1; then
    rm -rf "${test_venv}"
    printf "error: python3 venv cannot be created; ensure python3-venv and ensurepip are installed\n" >&2
    return 1
  fi
  if ! "${test_venv}/bin/python" -m pip --version >/dev/null 2>&1; then
    rm -rf "${test_venv}"
    printf "error: python3 venv was created without pip; ensure ensurepip is available\n" >&2
    return 1
  fi
  rm -rf "${test_venv}"
}

verify_runtime_packages() {
  verify_python_venv
  docker compose version >/dev/null
}

install_guest_tools_for_rootfs_smoke() {
  local wheel

  wheel="$(find "${PYTHON_WHEEL_DIR}" -maxdepth 1 -name 'tirosh_vitalserver_guest_tools-*.whl' -type f | sort | tail -n 1 || true)"
  if [ -z "${wheel}" ]; then
    printf "error: missing guest tools wheel under %s\n" "${PYTHON_WHEEL_DIR}" >&2
    return 1
  fi

  mkdir -p "${GUEST_TOOLS_HOME}"
  python3 -m venv --clear "${GUEST_TOOLS_VENV}"
  "${GUEST_TOOLS_VENV}/bin/pip" install --no-index --no-deps "${wheel}"
  ln -sf "${GUEST_TOOLS_VENV}/bin/tirosh-vitalserver-rootfs-smoke" /usr/local/bin/tirosh-vitalserver-rootfs-smoke
}

mount_share "${MOUNT_TAG}" "${MOUNT_POINT}"
mount_share "${VITAL_FILES_MOUNT_TAG}" "${VITAL_FILES_MOUNT_POINT}"
mkdir -p "${RUNTIME_DIR}"

install_runtime_packages
verify_runtime_packages
install_guest_tools_for_rootfs_smoke
tirosh-vitalserver-rootfs-smoke
systemctl enable docker
systemctl enable avahi-daemon

python3 - "${RUNTIME_MANIFEST_FILE}" "${READY_FILE}" <<'PY'
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

manifest_path = Path(sys.argv[1])
ready_path = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))


def command_output(command):
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    return (completed.stdout or completed.stderr).strip()


ready_path.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "runId": manifest["runId"],
            "readyAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "docker": command_output(["docker", "--version"]),
            "compose": command_output(["docker", "compose", "version"]),
            "manifest": str(manifest_path),
            "pythonVenv": "ready",
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY

printf "Air-gapped rootfs package prerequisites are ready.\n"
