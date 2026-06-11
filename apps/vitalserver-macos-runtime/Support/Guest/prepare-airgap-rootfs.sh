#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="tirosh"
MOUNT_POINT="/mnt/tirosh"
RUNTIME_DIR="${MOUNT_POINT}/run"
READY_FILE="${RUNTIME_DIR}/rootfs-ready"
RUNTIME_MANIFEST_FILE="${RUNTIME_DIR}/rootfs-runtime-manifest.json"
DOCKER_SMOKE_IMAGE="${VITALSERVER_DOCKER_SMOKE_IMAGE:-redis:3.2.12-alpine}"
LOCAL_DOCKER_SMOKE_IMAGE="vitalserver-rootfs-smoke:local"
BPF_JIT_SYSCTL_FILE="/etc/sysctl.d/99-vitalserver-bpf-jit.conf"

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

configure_bpf_jit_for_virtualization() {
  local actual

  cat > "${BPF_JIT_SYSCTL_FILE}" <<'EOF'
# VitalServer runs Docker inside Apple Virtualization on arm64.
# Keep BPF interpreted to avoid Ubuntu arm64 BPF JIT kernel panics during Docker netlink activity.
net.core.bpf_jit_enable = 0
EOF

  if [ ! -e /proc/sys/net/core/bpf_jit_enable ]; then
    printf "error: BPF JIT sysctl is missing; cannot prove Docker runtime guard\n" >&2
    return 1
  fi

  sysctl -w net.core.bpf_jit_enable=0 >/dev/null
  actual="$(cat /proc/sys/net/core/bpf_jit_enable)"
  if [ "${actual}" != "0" ]; then
    printf "error: BPF JIT remains enabled: net.core.bpf_jit_enable=%s\n" "${actual}" >&2
    return 1
  fi
}

json_string() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'
}

write_runtime_manifest() {
  local smoke_status="$1"
  local smoke_message="$2"
  local created_at kernel docker_version containerd_version runc_version compose_version bpf_jit_enable

  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kernel="$(uname -r 2>/dev/null || true)"
  docker_version="$(docker --version 2>/dev/null || true)"
  containerd_version="$(containerd --version 2>/dev/null || true)"
  runc_version="$(runc --version 2>/dev/null | head -n 1 || true)"
  compose_version="$(docker compose version 2>/dev/null || true)"
  bpf_jit_enable="$(cat /proc/sys/net/core/bpf_jit_enable 2>/dev/null || true)"

  cat > "${RUNTIME_MANIFEST_FILE}" <<EOF
{
  "schemaVersion": 1,
  "createdAt": $(printf "%s" "${created_at}" | json_string),
  "kernel": $(printf "%s" "${kernel}" | json_string),
  "docker": $(printf "%s" "${docker_version}" | json_string),
  "containerd": $(printf "%s" "${containerd_version}" | json_string),
  "runc": $(printf "%s" "${runc_version}" | json_string),
  "compose": $(printf "%s" "${compose_version}" | json_string),
  "bpfJIT": {
    "sysctlFile": $(printf "%s" "${BPF_JIT_SYSCTL_FILE}" | json_string),
    "net.core.bpf_jit_enable": $(printf "%s" "${bpf_jit_enable}" | json_string)
  },
  "dockerSmoke": {
    "image": $(printf "%s" "${DOCKER_SMOKE_IMAGE}" | json_string),
    "status": $(printf "%s" "${smoke_status}" | json_string),
    "message": $(printf "%s" "${smoke_message}" | json_string)
  }
}
EOF
}

run_docker_runtime_smoke() {
  local output smoke_image smoke_command temporary_image

  if ! docker image inspect "${DOCKER_SMOKE_IMAGE}" >/dev/null 2>&1; then
    build_local_docker_smoke_image
    smoke_image="${LOCAL_DOCKER_SMOKE_IMAGE}"
    smoke_command="/bin/busybox true"
    temporary_image=1
  else
    smoke_image="${DOCKER_SMOKE_IMAGE}"
    smoke_command="true"
    temporary_image=0
  fi

  if output="$(docker run --rm --network none "${smoke_image}" ${smoke_command} 2>&1)"; then
    if [ "${temporary_image}" -eq 1 ]; then
      docker image rm -f "${smoke_image}" >/dev/null 2>&1 || true
    fi
    DOCKER_SMOKE_IMAGE="${smoke_image}"
    write_runtime_manifest "passed" "docker runtime smoke passed"
    return 0
  fi

  if [ "${temporary_image}" -eq 1 ]; then
    docker image rm -f "${smoke_image}" >/dev/null 2>&1 || true
  fi
  DOCKER_SMOKE_IMAGE="${smoke_image}"
  write_runtime_manifest "failed" "${output}"
  printf "error: docker runtime smoke failed: %s\n" "${output}" >&2
  return 1
}

build_local_docker_smoke_image() {
  local workdir rootfs tarball

  workdir="$(mktemp -d)"
  rootfs="${workdir}/rootfs"
  tarball="${workdir}/rootfs.tar"
  mkdir -p "${rootfs}/bin"
  cp /bin/busybox "${rootfs}/bin/busybox"
  tar -C "${rootfs}" -cf "${tarball}" .
  if ! docker import "${tarball}" "${LOCAL_DOCKER_SMOKE_IMAGE}" >/dev/null; then
    rm -rf "${workdir}"
    return 1
  fi
  rm -rf "${workdir}"
}

configure_bpf_jit_for_virtualization
install_runtime_packages
verify_runtime_packages
run_docker_runtime_smoke
systemctl enable docker
systemctl enable avahi-daemon

{
  printf "ready_at=%s\n" "$(date -Iseconds)"
  printf "docker=%s\n" "$(docker --version 2>/dev/null || true)"
  printf "compose=%s\n" "$(docker compose version 2>/dev/null || true)"
  printf "manifest=%s\n" "${RUNTIME_MANIFEST_FILE}"
  printf "python_venv=ready\n"
} >"${READY_FILE}"

printf "Air-gapped rootfs package prerequisites are ready.\n"
