#!/usr/bin/env bash
set -euo pipefail

MOUNT_TAG="${TIROSH_SHARE_TAG:-tirosh}"
MOUNT_POINT="${TIROSH_SHARE_MOUNT:-/mnt/tirosh}"
DEPLOY_DIR="${TIROSH_DEPLOY_DIR:-${MOUNT_POINT}/deploy}"
APP_PORT="${VITALSERVER_VM_APP_PORT:-18080}"

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

export DEBIAN_FRONTEND=noninteractive
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

printf "VitalServer edge is ready on this VM at port 80.\n"
