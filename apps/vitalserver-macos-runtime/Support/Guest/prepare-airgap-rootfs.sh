#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="tirosh"
MOUNT_POINT="/mnt/tirosh"
VITAL_FILES_MOUNT_TAG="tirosh-vital-files"
VITAL_FILES_MOUNT_POINT="/mnt/tirosh-vital-files"
RUNTIME_DIR="${MOUNT_POINT}/run"
READY_FILE="${RUNTIME_DIR}/rootfs-ready"
RUNTIME_MANIFEST_FILE="${RUNTIME_DIR}/rootfs-runtime-manifest.json"
DOCKER_SMOKE_IMAGE="${VITALSERVER_DOCKER_SMOKE_IMAGE:-redis:3.2.12-alpine}"
LOCAL_DOCKER_SMOKE_IMAGE="vitalserver-rootfs-smoke:local"
COMPOSE_PROJECT_NAME="vitalserver-rootfs-smoke"
COMPOSE_FILE="${MOUNT_POINT}/deploy/compose.yaml"

if [ "$(id -u)" -ne 0 ]; then
  printf "error: run with sudo\n" >&2
  exit 1
fi

mkdir -p "${MOUNT_POINT}"
if ! mountpoint -q "${MOUNT_POINT}"; then
  mount -t virtiofs "${MOUNT_TAG}" "${MOUNT_POINT}"
fi
mkdir -p "${VITAL_FILES_MOUNT_POINT}"
if ! mountpoint -q "${VITAL_FILES_MOUNT_POINT}"; then
  mount -t virtiofs "${VITAL_FILES_MOUNT_TAG}" "${VITAL_FILES_MOUNT_POINT}"
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

json_string() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'
}

write_runtime_manifest() {
  local docker_smoke_status="$1"
  local docker_smoke_message="$2"
  local compose_smoke_status="$3"
  local compose_smoke_message="$4"
  local created_at kernel docker_version containerd_version runc_version compose_version

  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  kernel="$(uname -r 2>/dev/null || true)"
  docker_version="$(docker --version 2>/dev/null || true)"
  containerd_version="$(containerd --version 2>/dev/null || true)"
  runc_version="$(runc --version 2>/dev/null | head -n 1 || true)"
  compose_version="$(docker compose version 2>/dev/null || true)"

  cat > "${RUNTIME_MANIFEST_FILE}" <<EOF
{
  "schemaVersion": 1,
  "createdAt": $(printf "%s" "${created_at}" | json_string),
  "kernel": $(printf "%s" "${kernel}" | json_string),
  "docker": $(printf "%s" "${docker_version}" | json_string),
  "containerd": $(printf "%s" "${containerd_version}" | json_string),
  "runc": $(printf "%s" "${runc_version}" | json_string),
  "compose": $(printf "%s" "${compose_version}" | json_string),
  "dockerSmoke": {
    "image": $(printf "%s" "${DOCKER_SMOKE_IMAGE}" | json_string),
    "status": $(printf "%s" "${docker_smoke_status}" | json_string),
    "message": $(printf "%s" "${docker_smoke_message}" | json_string)
  },
  "composeSmoke": {
    "project": $(printf "%s" "${COMPOSE_PROJECT_NAME}" | json_string),
    "status": $(printf "%s" "${compose_smoke_status}" | json_string),
    "message": $(printf "%s" "${compose_smoke_message}" | json_string)
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
    write_runtime_manifest \
      "passed" \
      "docker runtime smoke passed" \
      "not-run" \
      "compose smoke has not run yet"
    return 0
  fi

  if [ "${temporary_image}" -eq 1 ]; then
    docker image rm -f "${smoke_image}" >/dev/null 2>&1 || true
  fi
  DOCKER_SMOKE_IMAGE="${smoke_image}"
  write_runtime_manifest \
    "failed" \
    "${output}" \
    "not-run" \
    "compose smoke was skipped because Docker runtime smoke failed"
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

compose_smoke_cleanup() {
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    -f "${COMPOSE_FILE}" \
    down -v --remove-orphans >/dev/null 2>&1 || true
}

compose_smoke_logs() {
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    -f "${COMPOSE_FILE}" \
    ps >&2 || true
  docker compose \
    --project-name "${COMPOSE_PROJECT_NAME}" \
    -f "${COMPOSE_FILE}" \
    logs --tail=200 >&2 || true
}

compose_smoke() {
  docker compose --project-name "${COMPOSE_PROJECT_NAME}" -f "${COMPOSE_FILE}" "$@"
}

wait_for_compose_edge_ready() {
  local deadline code curl_status

  deadline=$(( $(date +%s) + 600 ))
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    code="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1/ready" 2>/dev/null)" \
      && curl_status=0 \
      || curl_status=$?

    if [ "${curl_status}" -eq 0 ] && [ "${code}" -ge 200 ] && [ "${code}" -lt 300 ]; then
      return 0
    fi
    sleep 3
  done
  return 1
}

run_compose_runtime_smoke() {
  local output

  if ! output="$(
    {
      compose_smoke build app audit-proxy vitaldb-observer
      compose_smoke up -d redis
      compose_smoke up -d app audit-proxy vitaldb-observer redis-ui swagger-ui
      compose_smoke up -d edge
      wait_for_compose_edge_ready
    } 2>&1
  )"; then
    write_runtime_manifest \
      "passed" \
      "docker runtime smoke passed" \
      "failed" \
      "${output}"
    printf "error: compose runtime smoke failed: %s\n" "${output}" >&2
    compose_smoke_logs
    compose_smoke_cleanup
    return 1
  fi

  write_runtime_manifest \
    "passed" \
    "docker runtime smoke passed" \
    "passed" \
    "compose runtime smoke passed"
  compose_smoke_cleanup
}

install_runtime_packages
verify_runtime_packages
run_docker_runtime_smoke
run_compose_runtime_smoke
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
