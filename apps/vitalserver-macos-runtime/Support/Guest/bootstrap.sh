#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="${TIROSH_SHARE_TAG:-tirosh}"
MOUNT_POINT="${TIROSH_SHARE_MOUNT:-/mnt/tirosh}"
VITAL_FILES_MOUNT_TAG="${TIROSH_VITAL_FILES_SHARE_TAG:-tirosh-vital-files}"
VITAL_FILES_MOUNT_POINT="${TIROSH_VITAL_FILES_SHARE_MOUNT:-/mnt/tirosh-vital-files}"
DEPLOY_DIR="${TIROSH_DEPLOY_DIR:-${MOUNT_POINT}/deploy}"
RUNTIME_DIR="${MOUNT_POINT}/run"
RUNTIME_STATE_FILE="${RUNTIME_DIR}/runtime-state.json"
BOOTSTRAP_RESULT_FILE="${RUNTIME_DIR}/bootstrap-result.json"
BOOTSTRAP_RESULT_WRITTEN=0
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

write_bootstrap_result() {
  local status="$1"
  local message="$2"
  local reason_code="${3:-}"
  local boot_id updated_at reason_codes_json

  mkdir -p "${RUNTIME_DIR}"
  boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -n "${reason_code}" ]; then
    reason_codes_json="[\"${reason_code}\"]"
  else
    reason_codes_json="[]"
  fi

cat > "${BOOTSTRAP_RESULT_FILE}" <<EOF
{
  "bootID" : "${boot_id}",
  "message" : "${message}",
  "operation" : "bootstrap",
  "reasonCodes" : ${reason_codes_json},
  "schemaVersion" : 3,
  "status" : "${status}",
  "updatedAt" : "${updated_at}"
}
EOF
  BOOTSTRAP_RESULT_WRITTEN=1
}

write_bootstrap_failed_on_exit() {
  local status="$?"
  if [ "${status}" -ne 0 ] && [ "${BOOTSTRAP_RESULT_WRITTEN}" -eq 0 ]; then
    write_bootstrap_result "failed" "Guest bootstrap failed." "guest-bootstrap-failed" || true
  fi
  exit "${status}"
}

require_deploy_bundle() {
  if [ ! -f "${DEPLOY_DIR}/compose.yaml" ]; then
    printf "error: missing %s/compose.yaml\n" "${DEPLOY_DIR}" >&2
    printf "Run 'make vm-stage' on macOS first.\n" >&2
    exit 1
  fi

  if [ ! -f "${DEPLOY_DIR}/runtime-config.json" ]; then
    printf "error: missing %s/runtime-config.json\n" "${DEPLOY_DIR}" >&2
    exit 1
  fi
}

write_runtime_state() {
  /usr/local/bin/tirosh-runtime-state once
}

expand_root_filesystem() {
  local root_source parent_device partition_number filesystem_type

  root_source="$(findmnt -n -o SOURCE /)"
  parent_device="$(lsblk -no PKNAME "${root_source}" 2>/dev/null | head -n 1 || true)"
  partition_number="$(lsblk -no PARTNUM "${root_source}" 2>/dev/null | head -n 1 || true)"
  filesystem_type="$(findmnt -n -o FSTYPE /)"

  if [ -z "${partition_number}" ]; then
    case "${root_source}" in
      /dev/nvme*n*p[0-9]* | /dev/mmcblk*p[0-9]*)
        partition_number="${root_source##*p}"
        ;;
      /dev/*[0-9])
        partition_number="${root_source##*[!0-9]}"
        ;;
    esac
  fi

  if [ -z "${parent_device}" ] && [ -n "${partition_number}" ]; then
    case "${root_source}" in
      /dev/nvme*n*p"${partition_number}" | /dev/mmcblk*p"${partition_number}")
        parent_device="${root_source#/dev/}"
        parent_device="${parent_device%p${partition_number}}"
        ;;
      /dev/*"${partition_number}")
        parent_device="${root_source#/dev/}"
        parent_device="${parent_device%${partition_number}}"
        ;;
    esac
  fi

  if [ -z "${parent_device}" ] || [ -z "${partition_number}" ]; then
    printf "warning: could not resolve root partition for resize: %s\n" "${root_source}" >&2
    return
  fi

  if command -v growpart >/dev/null 2>&1; then
    growpart "/dev/${parent_device}" "${partition_number}" || true
  else
    printf "warning: growpart is not available; root partition may stay small\n" >&2
  fi

  case "${filesystem_type}" in
    ext2 | ext3 | ext4)
      resize2fs "${root_source}" || true
      ;;
    xfs)
      xfs_growfs / || true
      ;;
    *)
      printf "warning: unsupported root filesystem for resize: %s\n" "${filesystem_type}" >&2
      ;;
  esac

  df -h /
}

runtime_packages_ready() {
  command -v curl >/dev/null 2>&1 \
    && command -v docker >/dev/null 2>&1 \
    && command -v python3 >/dev/null 2>&1 \
    && python3 -m venv --help >/dev/null 2>&1 \
    && command -v fuser >/dev/null 2>&1 \
    && command -v avahi-daemon >/dev/null 2>&1 \
    && command -v growpart >/dev/null 2>&1 \
    && docker compose version >/dev/null 2>&1
}

missing_runtime_packages() {
  local missing=()

  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v docker >/dev/null 2>&1 || missing+=("docker")
  command -v python3 >/dev/null 2>&1 || missing+=("python3-minimal")
  python3 -m venv --help >/dev/null 2>&1 || missing+=("python3-venv")
  command -v fuser >/dev/null 2>&1 || missing+=("psmisc")
  command -v avahi-daemon >/dev/null 2>&1 || missing+=("avahi-daemon")
  command -v growpart >/dev/null 2>&1 || missing+=("growpart")
  docker compose version >/dev/null 2>&1 || missing+=("docker compose")

  printf "%s\n" "${missing[@]}"
}

require_runtime_packages() {
  if runtime_packages_ready; then
    printf "Runtime packages are available in the air-gapped rootfs.\n"
    return
  fi

  printf "error: missing runtime package in air-gapped rootfs\n" >&2
  printf "The target bootstrap never runs apt-get. Rebuild the package rootfs with make vm-golden-rootfs.\n" >&2
  printf "Required commands/services: curl, docker, docker compose, python3-minimal, python3-venv, psmisc, avahi-daemon, growpart.\n" >&2
  printf "Missing commands/services:\n" >&2
  missing_runtime_packages | sed 's/^/  - /' >&2
  write_bootstrap_result "failed" "Missing runtime packages." "guest-bootstrap-missing-runtime-packages"
  exit 1
}

install_guest_tools() {
  local wheel
  local command

  wheel="$(find "${PYTHON_WHEEL_DIR}" -maxdepth 1 -name 'tirosh_vitalserver_guest_tools-*.whl' -type f | sort | tail -n 1 || true)"
  if [ -z "${wheel}" ]; then
    printf "error: missing guest tools wheel under %s\n" "${PYTHON_WHEEL_DIR}" >&2
    return 1
  fi

  mkdir -p "${GUEST_TOOLS_HOME}"
  python3 -m venv --clear "${GUEST_TOOLS_VENV}"
  "${GUEST_TOOLS_VENV}/bin/pip" install --no-index --no-deps "${wheel}"
  for command in \
    tirosh-guest-observed \
    tirosh-guest-observe \
    tirosh-guest-container-logs \
    tirosh-guest-diagnostics \
    tirosh-runtime-env \
    tirosh-write-runtime-state \
    tirosh-runtime-state \
    tirosh-vitalserver-health \
    tirosh-vitalserver-compose \
    tirosh-vitalserver-command-poller \
    tirosh-vitalserver-redis-backup \
    tirosh-vitalserver-repair-datastore \
    tirosh-vitalserver-activate-update \
    tirosh-vitalserver-prepare-update-shutdown; do
    ln -sf "${GUEST_TOOLS_VENV}/bin/${command}" "/usr/local/bin/${command}"
  done
  ln -sf "${GUEST_TOOLS_VENV}/bin/tirosh-guest-container-logs" /usr/local/bin/tirosh-vitalserver-container-logs
  ln -sf "${GUEST_TOOLS_VENV}/bin/tirosh-guest-diagnostics" /usr/local/bin/tirosh-vitalserver-diagnostics
}

install_guest_runtime_files() {
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-runtime-env" /usr/local/bin/tirosh-runtime-env
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-write-runtime-state" /usr/local/bin/tirosh-write-runtime-state
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-runtime-state" /usr/local/bin/tirosh-runtime-state
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-compose" /usr/local/bin/tirosh-vitalserver-compose
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-health" /usr/local/bin/tirosh-vitalserver-health
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-container-logs" /usr/local/bin/tirosh-vitalserver-container-logs
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-diagnostics" /usr/local/bin/tirosh-vitalserver-diagnostics
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-redis-backup" /usr/local/bin/tirosh-vitalserver-redis-backup
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-repair-datastore" /usr/local/bin/tirosh-vitalserver-repair-datastore
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-activate-update" /usr/local/bin/tirosh-vitalserver-activate-update
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-prepare-update-shutdown" /usr/local/bin/tirosh-vitalserver-prepare-update-shutdown
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-command-poller" /usr/local/bin/tirosh-vitalserver-command-poller
  install_guest_tools

  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-guest-observability.service" /etc/systemd/system/tirosh-guest-observability.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-runtime-state.service" /etc/systemd/system/tirosh-runtime-state.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-compose.service" /etc/systemd/system/tirosh-vitalserver-compose.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-testkit.service" /etc/systemd/system/tirosh-vitalserver-testkit.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-container-logs.service" /etc/systemd/system/tirosh-vitalserver-container-logs.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-redis-backup.service" /etc/systemd/system/tirosh-vitalserver-redis-backup.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-redis-backup.timer" /etc/systemd/system/tirosh-vitalserver-redis-backup.timer
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-repair-datastore.service" /etc/systemd/system/tirosh-vitalserver-repair-datastore.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-activate-update.service" /etc/systemd/system/tirosh-vitalserver-activate-update.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-prepare-update-shutdown.service" /etc/systemd/system/tirosh-vitalserver-prepare-update-shutdown.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-command-poller.service" /etc/systemd/system/tirosh-vitalserver-command-poller.service

  systemctl daemon-reload
  systemctl disable --now tirosh-vitalserver-redis-backup.path >/dev/null 2>&1 || true
  systemctl disable --now tirosh-vitalserver-repair-datastore.path >/dev/null 2>&1 || true
  systemctl disable --now tirosh-vitalserver-activate-update.path >/dev/null 2>&1 || true
  systemctl disable --now tirosh-vitalserver-prepare-update-shutdown.path >/dev/null 2>&1 || true
  systemctl enable tirosh-runtime-state.service
  systemctl enable tirosh-vitalserver-compose.service
  systemctl enable tirosh-vitalserver-testkit.service
  systemctl enable --now tirosh-vitalserver-container-logs.service
  systemctl enable --now tirosh-vitalserver-redis-backup.timer
  systemctl enable --now tirosh-vitalserver-command-poller.service
  systemctl enable --now tirosh-guest-observability.service
}

load_bundled_docker_images() {
  local image_dir="${DEPLOY_DIR}/docker-images"
  local loaded=0

  if [ ! -d "${image_dir}" ]; then
    return
  fi

  for image_bundle in "${image_dir}"/*.tar "${image_dir}"/*.tar.gz "${image_dir}"/*.tgz; do
    [ -e "${image_bundle}" ] || continue
    printf "Loading Docker image bundle: %s\n" "${image_bundle}"
    docker load -i "${image_bundle}"
    loaded=1
  done

  if [ "${loaded}" -eq 1 ]; then
    printf "Bundled Docker images are loaded.\n"
  fi
}

cleanup_docker_cache() {
  docker image prune -f >/dev/null 2>&1 || true
}

start_optional_testkit() {
  if [ "${TIROSH_TESTKIT_ENABLED:-0}" != "1" ]; then
    return
  fi

  printf "Scheduling optional TestKit provisioning via systemd.\n"
  systemctl reset-failed tirosh-vitalserver-testkit.service >/dev/null 2>&1 || true
  systemctl restart --no-block tirosh-vitalserver-testkit.service || \
    printf "warning: failed to schedule optional TestKit provisioning\n" >&2
}

wait_for_vitalserver_edge() {
  local deadline code http_status

  printf "Waiting for VitalServer edge readiness: http://127.0.0.1/ready\n"
  deadline=$(( $(date +%s) + 600 ))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    code="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1/ready" 2>/dev/null)" \
      && http_status=0 \
      || http_status=$?

    if [ "${http_status}" -eq 0 ] && [ "${code}" -ge 200 ] && [ "${code}" -lt 300 ]; then
      printf "VitalServer edge is ready: %s\n" "${code}"
      write_runtime_state
      return
    fi

    sleep 3
  done

  printf "error: VitalServer edge did not become ready\n" >&2
  docker compose \
    --project-name vitalserver \
    -f "${DEPLOY_DIR}/compose.yaml" \
    ps >&2 || true
  docker compose \
    --project-name vitalserver \
    -f "${DEPLOY_DIR}/compose.yaml" \
    logs --tail=200 >&2 || true
  df -h / >&2 || true
  exit 1
}

mount_share "${MOUNT_TAG}" "${MOUNT_POINT}"
mount_share "${VITAL_FILES_MOUNT_TAG}" "${VITAL_FILES_MOUNT_POINT}"
trap write_bootstrap_failed_on_exit EXIT
write_bootstrap_result "running" "Guest bootstrap is running."
require_deploy_bundle

export DEBIAN_FRONTEND=noninteractive
expand_root_filesystem
require_runtime_packages

install_guest_runtime_files
write_runtime_state

systemctl enable --now docker
hostnamectl set-hostname "${TIROSH_GUEST_HOSTNAME:-tirosh-vitalserver}"
systemctl enable --now avahi-daemon

mkdir -p "${VITAL_FILES_MOUNT_POINT}" "${MOUNT_POINT}/vr-release"

load_bundled_docker_images
cleanup_docker_cache

if ! docker image inspect vitalserver:2.3.4 >/dev/null 2>&1; then
  docker compose \
    --project-name vitalserver \
    -f "${DEPLOY_DIR}/compose.yaml" \
    build app
fi
if ! docker image inspect vitalserver-audit-proxy:0.1.0 >/dev/null 2>&1; then
  docker compose \
    --project-name vitalserver \
    -f "${DEPLOY_DIR}/compose.yaml" \
    build audit-proxy
fi

eval "$(/usr/local/bin/tirosh-runtime-env "${DEPLOY_DIR}/runtime-config.json")"
/usr/local/bin/tirosh-vitalserver-compose up

wait_for_vitalserver_edge
systemctl restart tirosh-runtime-state.service

write_bootstrap_result "completed" "Guest bootstrap completed."
printf "VitalServer edge is ready on this VM at port 80.\n"
start_optional_testkit
