#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="${TIROSH_SHARE_TAG:-tirosh}"
MOUNT_POINT="${TIROSH_SHARE_MOUNT:-/mnt/tirosh}"
DEPLOY_DIR="${TIROSH_DEPLOY_DIR:-${MOUNT_POINT}/deploy}"
APP_PORT="${VITALSERVER_VM_APP_PORT:-18080}"
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

if [ ! -f "${DEPLOY_DIR}/compose.yaml" ]; then
  printf "error: missing %s/compose.yaml\n" "${DEPLOY_DIR}" >&2
  printf "Run 'make vm-stage' on macOS first.\n" >&2
  exit 1
fi

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

export DEBIAN_FRONTEND=noninteractive
write_vm_ip
wait_for_network_time
apt-get update
apt-get install -y \
  avahi-daemon \
  binfmt-support \
  ca-certificates \
  curl \
  docker.io \
  nginx \
  qemu-user-static

if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y docker-compose-v2 \
    || apt-get install -y docker-compose-plugin
fi

if ! docker compose version >/dev/null 2>&1; then
  printf "error: Docker Compose v2 is not available\n" >&2
  exit 1
fi

systemctl enable --now docker
systemctl enable --now nginx
hostnamectl set-hostname "${TIROSH_GUEST_HOSTNAME:-tirosh-vitalserver}"
systemctl enable --now avahi-daemon
install_vm_ip_writer

mkdir -p "${MOUNT_POINT}/vital-files" "${MOUNT_POINT}/vr-release"

tmp_nginx="$(mktemp)"
sed "s/__VITALSERVER_APP_PORT__/${APP_PORT}/g" \
  "${DEPLOY_DIR}/nginx/vitalserver.conf" >"${tmp_nginx}"
install -m 0644 "${tmp_nginx}" /etc/nginx/sites-available/vitalserver
rm -f "${tmp_nginx}"
ln -sfn /etc/nginx/sites-available/vitalserver /etc/nginx/sites-enabled/vitalserver
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

docker compose \
  --project-name vitalserver \
  --env-file "${DEPLOY_DIR}/.env" \
  -f "${DEPLOY_DIR}/compose.yaml" \
  up -d --build

write_vm_ip

printf "VitalServer edge is ready on this VM at port 80.\n"
