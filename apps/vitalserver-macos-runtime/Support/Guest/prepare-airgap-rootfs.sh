#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="tirosh"
MOUNT_POINT="/mnt/tirosh"
RUNTIME_DIR="${MOUNT_POINT}/run"
READY_FILE="${RUNTIME_DIR}/rootfs-ready"

if [ "$(id -u)" -ne 0 ]; then
  printf "error: run with sudo\n" >&2
  exit 1
fi

mkdir -p "${MOUNT_POINT}"
if ! mountpoint -q "${MOUNT_POINT}"; then
  mount -t virtiofs "${MOUNT_TAG}" "${MOUNT_POINT}"
fi
mkdir -p "${RUNTIME_DIR}"

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

install_runtime_packages
verify_runtime_packages
systemctl enable docker
systemctl enable avahi-daemon

{
  printf "ready_at=%s\n" "$(date -Iseconds)"
  printf "docker=%s\n" "$(docker --version 2>/dev/null || true)"
  printf "compose=%s\n" "$(docker compose version 2>/dev/null || true)"
  printf "python_venv=ready\n"
} >"${READY_FILE}"

printf "Air-gapped rootfs package prerequisites are ready.\n"
