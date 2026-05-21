#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="${TIROSH_SHARE_TAG:-tirosh}"
MOUNT_POINT="${TIROSH_SHARE_MOUNT:-/mnt/tirosh}"
VITAL_FILES_MOUNT_TAG="${TIROSH_VITAL_FILES_SHARE_TAG:-tirosh-vital-files}"
VITAL_FILES_MOUNT_POINT="${TIROSH_VITAL_FILES_SHARE_MOUNT:-/mnt/tirosh-vital-files}"
DEPLOY_DIR="${TIROSH_DEPLOY_DIR:-${MOUNT_POINT}/deploy}"
RUNTIME_DIR="${MOUNT_POINT}/run"
RUNTIME_STATE_FILE="${RUNTIME_DIR}/runtime-state.json"

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
  /usr/local/bin/tirosh-write-runtime-state "${RUNTIME_STATE_FILE}" "${1:-}"
}

wait_for_network_time() {
  timedatectl set-ntp true >/dev/null 2>&1 || true
  systemctl restart systemd-timesyncd >/dev/null 2>&1 || true

  for _ in $(seq 1 60); do
    if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then
      return
    fi
    sleep 1
  done

  printf "warning: network time is not synchronized yet\n" >&2
}

disable_flash_kernel_hook() {
  local hook="/etc/initramfs/post-update.d/flash-kernel"

  if [ -x "${hook}" ]; then
    # Ubuntu arm64 cloud images may include flash-kernel, but Apple
    # Virtualization boots the kernel/initrd supplied by macOS. The guest-side
    # flash-kernel hook can fail with "Unsupported platform" and block apt.
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

qemu_user_ready() {
  case "$(uname -m)" in
    x86_64 | amd64)
      return 0
      ;;
    *)
      command -v qemu-x86_64-static >/dev/null 2>&1
      ;;
  esac
}

runtime_packages_ready() {
  command -v curl >/dev/null 2>&1 \
    && command -v docker >/dev/null 2>&1 \
    && command -v avahi-daemon >/dev/null 2>&1 \
    && command -v growpart >/dev/null 2>&1 \
    && docker compose version >/dev/null 2>&1 \
    && qemu_user_ready
}

install_runtime_packages() {
  wait_for_network_time
  disable_flash_kernel_hook
  remove_flash_kernel_package
  repair_package_state

  apt-get update
  apt-get install -y \
    avahi-daemon \
    binfmt-support \
    ca-certificates \
    cloud-guest-utils \
    curl \
    docker.io \
    qemu-user-static

  if ! docker compose version >/dev/null 2>&1; then
    apt-get install -y docker-compose-v2 \
      || apt-get install -y docker-compose-plugin
  fi
}

install_guest_runtime_files() {
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-runtime-env" /usr/local/bin/tirosh-runtime-env
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-write-runtime-state" /usr/local/bin/tirosh-write-runtime-state
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-runtime-state" /usr/local/bin/tirosh-runtime-state
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-compose" /usr/local/bin/tirosh-vitalserver-compose
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-health" /usr/local/bin/tirosh-vitalserver-health
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-diagnostics" /usr/local/bin/tirosh-vitalserver-diagnostics
  install -m 0755 "${DEPLOY_DIR}/bin/tirosh-vitalserver-redis-backup" /usr/local/bin/tirosh-vitalserver-redis-backup

  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-runtime-state.service" /etc/systemd/system/tirosh-runtime-state.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-compose.service" /etc/systemd/system/tirosh-vitalserver-compose.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-redis-backup.service" /etc/systemd/system/tirosh-vitalserver-redis-backup.service
  install -m 0644 "${DEPLOY_DIR}/systemd/tirosh-vitalserver-redis-backup.timer" /etc/systemd/system/tirosh-vitalserver-redis-backup.timer

  systemctl daemon-reload
  systemctl enable tirosh-runtime-state.service
  systemctl enable tirosh-vitalserver-compose.service
  systemctl enable --now tirosh-vitalserver-redis-backup.timer
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

wait_for_vitalserver_edge() {
  local deadline code http_status

  printf "Waiting for VitalServer edge: http://127.0.0.1/\n"
  deadline=$(( "$(date +%s)" + 600 ))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    code="$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1/" 2>/dev/null)" \
      && http_status=0 \
      || http_status=$?

    if [ "${http_status}" -eq 0 ] && [ "${code}" -ge 200 ] && [ "${code}" -lt 400 ]; then
      printf "VitalServer edge is ready: %s\n" "${code}"
      write_runtime_state "${code}"
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
require_deploy_bundle

export DEBIAN_FRONTEND=noninteractive
expand_root_filesystem

if runtime_packages_ready; then
  printf "Runtime packages are already available; skipping apt install.\n"
else
  install_runtime_packages
fi

if ! docker compose version >/dev/null 2>&1; then
  printf "error: Docker Compose v2 is not available\n" >&2
  exit 1
fi

install_guest_runtime_files
write_runtime_state

systemctl enable --now docker
systemctl enable --now binfmt-support >/dev/null 2>&1 || true
hostnamectl set-hostname "${TIROSH_GUEST_HOSTNAME:-tirosh-vitalserver}"
systemctl enable --now avahi-daemon

mkdir -p "${VITAL_FILES_MOUNT_POINT}" "${MOUNT_POINT}/vr-release"

load_bundled_docker_images
cleanup_docker_cache

compose_build_args=()
if ! docker image inspect vitalserver:2.3.4 >/dev/null 2>&1; then
  compose_build_args+=(--build)
fi

eval "$(/usr/local/bin/tirosh-runtime-env "${DEPLOY_DIR}/runtime-config.json")"
docker compose \
  --project-name vitalserver \
  -f "${DEPLOY_DIR}/compose.yaml" \
  up -d "${compose_build_args[@]}"

wait_for_vitalserver_edge
write_runtime_state "200"

printf "VitalServer edge is ready on this VM at port 80.\n"
