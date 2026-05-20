#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="${TIROSH_SHARE_TAG:-tirosh}"
MOUNT_POINT="${TIROSH_SHARE_MOUNT:-/mnt/tirosh}"
VITAL_FILES_MOUNT_TAG="${TIROSH_VITAL_FILES_SHARE_TAG:-tirosh-vital-files}"
VITAL_FILES_MOUNT_POINT="${TIROSH_VITAL_FILES_SHARE_MOUNT:-/mnt/tirosh-vital-files}"
DEPLOY_DIR="${TIROSH_DEPLOY_DIR:-${MOUNT_POINT}/deploy}"
APP_PORT="${VITALSERVER_VM_APP_PORT:-18080}"
REDIS_UI_PORT="${REDIS_UI_PORT:-18081}"
SWAGGER_UI_PORT="${SWAGGER_UI_PORT:-18082}"
RUNTIME_DIR="${MOUNT_POINT}/run"
VM_IP_FILE="${RUNTIME_DIR}/vm-ip"

if [ "$(id -u)" -ne 0 ]; then
  printf "error: run with sudo\n" >&2
  exit 1
fi

mkdir -p "${MOUNT_POINT}"
if ! mountpoint -q "${MOUNT_POINT}"; then
  # The launcher exposes the macOS runtime directory through VirtioFS.
  mount -t virtiofs "${MOUNT_TAG}" "${MOUNT_POINT}"
fi

mkdir -p "${VITAL_FILES_MOUNT_POINT}"
if ! mountpoint -q "${VITAL_FILES_MOUNT_POINT}"; then
  # Store .vital files in the operator-selected macOS directory.
  mount -t virtiofs "${VITAL_FILES_MOUNT_TAG}" "${VITAL_FILES_MOUNT_POINT}"
fi

if [ ! -f "${DEPLOY_DIR}/compose.yaml" ]; then
  printf "error: missing %s/compose.yaml\n" "${DEPLOY_DIR}" >&2
  printf "Run 'make vm-stage' on macOS first.\n" >&2
  exit 1
fi

load_runtime_config() {
  local config_file="${DEPLOY_DIR}/runtime-config.json"

  if [ ! -f "${config_file}" ]; then
    printf "error: missing %s\n" "${config_file}" >&2
    exit 1
  fi

  eval "$(
    python3 - "${config_file}" <<'PY'
import json
import shlex
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)


def emit(name, value):
    print(f"export {name}={shlex.quote(str(value))}")


emit("VITALSERVER_HTTP_PORT", config.get("vitalserverHttpPort", 18080))
emit("VITALSERVER_REDIS_HOST", config.get("redisHost", "redis"))
emit("VITALSERVER_REDIS_PORT", config.get("redisPort", 6379))
emit("VITALSERVER_TRUST_PROXY", "1" if config.get("trustProxy", True) else "0")
emit("VITALSERVER_PUBLIC_HOST", config.get("publicHost", ""))
emit("VITALSERVER_PUBLIC_PORT", config.get("publicPort", ""))
emit("VITALSERVER_ADMIN_PASSWORD", config.get("adminPassword", "admin"))
emit("VITALSERVER_VITAL_FILES_DIR", config.get("vitalFilesDirectory", "/mnt/tirosh-vital-files"))
emit("REDIS_UI_PORT", config.get("redisUiPort", 18081))
emit("SWAGGER_UI_PORT", config.get("swaggerUiPort", 18082))
PY
  )"

  APP_PORT="${VITALSERVER_HTTP_PORT}"
}

install_vm_ip_writer() {
  install -m 0755 /dev/stdin /usr/local/bin/tirosh-write-vm-ip <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="${TIROSH_SHARE_TAG:-tirosh}"
MOUNT_POINT="${TIROSH_SHARE_MOUNT:-/mnt/tirosh}"
RUNTIME_DIR="${MOUNT_POINT}/run"
VM_IP_FILE="${RUNTIME_DIR}/vm-ip"

mkdir -p "${MOUNT_POINT}"
if ! mountpoint -q "${MOUNT_POINT}"; then
  mount -t virtiofs "${MOUNT_TAG}" "${MOUNT_POINT}"
fi

mkdir -p "${RUNTIME_DIR}"
hostname -I \
  | tr ' ' '\n' \
  | awk 'NF && $1 !~ /^127\./ && $1 !~ /^169\.254\./ { print $1; exit }' \
  >"${VM_IP_FILE}"
SCRIPT

  cat >/etc/systemd/system/tirosh-vm-ip.service <<'UNIT'
[Unit]
Description=Write Tirosh VM IP to shared runtime directory
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tirosh-write-vm-ip

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable tirosh-vm-ip.service
}

write_vm_ip() {
  mkdir -p "${RUNTIME_DIR}"
  hostname -I \
    | tr ' ' '\n' \
    | awk 'NF && $1 !~ /^127\\./ && $1 !~ /^169\\.254\\./ { print $1; exit }' \
    >"${VM_IP_FILE}"
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
  parent_device="$(lsblk -no PKNAME "${root_source}" 2>/dev/null | head -n 1)"
  partition_number="$(lsblk -no PARTNUM "${root_source}" 2>/dev/null | head -n 1)"
  filesystem_type="$(findmnt -n -o FSTYPE /)"

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
    && command -v nginx >/dev/null 2>&1 \
    && command -v avahi-daemon >/dev/null 2>&1 \
    && command -v growpart >/dev/null 2>&1 \
    && docker compose version >/dev/null 2>&1 \
    && qemu_user_ready
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
    nginx \
    qemu-user-static

  if ! docker compose version >/dev/null 2>&1; then
    apt-get install -y docker-compose-v2 \
      || apt-get install -y docker-compose-plugin
  fi
}

export DEBIAN_FRONTEND=noninteractive
write_vm_ip
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

load_runtime_config

systemctl enable --now docker
systemctl enable --now nginx
systemctl enable --now binfmt-support >/dev/null 2>&1 || true
hostnamectl set-hostname "${TIROSH_GUEST_HOSTNAME:-tirosh-vitalserver}"
systemctl enable --now avahi-daemon
install_vm_ip_writer

mkdir -p "${VITAL_FILES_MOUNT_POINT}" "${MOUNT_POINT}/vr-release"

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

wait_for_vitalserver_http() {
  local deadline code http_status

  printf "Waiting for VitalServer app: http://127.0.0.1:%s/\n" "${APP_PORT}"
  deadline=$(( "$(date +%s)" + 600 ))

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    code="$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${APP_PORT}/" 2>/dev/null)" \
      && http_status=0 \
      || http_status=$?

    if [ "${http_status}" -eq 0 ] && [ "${code}" -ge 200 ] && [ "${code}" -lt 400 ]; then
      printf "VitalServer app is ready: %s\n" "${code}"
      return
    fi

    sleep 3
  done

  printf "error: VitalServer app did not become ready\n" >&2
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

tmp_nginx="$(mktemp)"
sed \
  -e "s/__VITALSERVER_APP_PORT__/${APP_PORT}/g" \
  -e "s/__REDIS_UI_PORT__/${REDIS_UI_PORT}/g" \
  -e "s/__SWAGGER_UI_PORT__/${SWAGGER_UI_PORT}/g" \
  "${DEPLOY_DIR}/nginx/vitalserver.conf" >"${tmp_nginx}"
install -m 0644 "${tmp_nginx}" /etc/nginx/sites-available/vitalserver
rm -f "${tmp_nginx}"
ln -sfn /etc/nginx/sites-available/vitalserver /etc/nginx/sites-enabled/vitalserver
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

load_bundled_docker_images

compose_build_args=()
if ! docker image inspect vitalserver:2.3.4 >/dev/null 2>&1; then
  compose_build_args+=(--build)
fi

docker compose \
  --project-name vitalserver \
  -f "${DEPLOY_DIR}/compose.yaml" \
  up -d "${compose_build_args[@]}"

wait_for_vitalserver_http
write_vm_ip

printf "VitalServer edge is ready on this VM at port 80.\n"
