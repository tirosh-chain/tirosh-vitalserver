#!/usr/bin/env bash
set -euo pipefail

main() {
  resolve_settings
  require_tools
  prepare_seed_directory
  write_meta_data
  write_user_data
  build_seed_iso
  print_result
}

resolve_settings() {
  images_dir="${VM_IMAGE_DIR:-${VM_HOME:-${HOME}/.tirosh/vitalserver-vm}/images}"
  seed_dir="${VM_CLOUD_INIT_DIR:-${images_dir}/cloud-init-seed}"
  seed_iso="${VM_CLOUD_INIT_ISO:-${images_dir}/seed.iso}"
  hostname="${VM_CLOUD_INIT_HOSTNAME:-tirosh-vitalserver}"
  username="${VM_CLOUD_INIT_USER:-ubuntu}"
  password="${VM_CLOUD_INIT_PASSWORD:-ubuntu}"
  ssh_key_path="${VM_CLOUD_INIT_SSH_KEY:-${HOME}/.ssh/id_ed25519.pub}"
}

require_tools() {
  require_command hdiutil || fail "missing hdiutil"
}

prepare_seed_directory() {
  rm -rf "${seed_dir}"
  mkdir -p "${seed_dir}" "$(dirname "${seed_iso}")"
}

write_meta_data() {
  cat >"${seed_dir}/meta-data" <<EOF
instance-id: tirosh-vitalserver
local-hostname: ${hostname}
EOF
}

write_user_data() {
  ssh_keys="$(cloud_init_ssh_keys)"

  cat >"${seed_dir}/user-data" <<EOF
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true
ssh_pwauth: true
disable_root: true
users:
  - default
  - name: ${username}
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
${ssh_keys}
chpasswd:
  expire: false
  users:
    - name: ${username}
      password: ${password}
      type: text
EOF
}

cloud_init_ssh_keys() {
  if [ ! -s "${ssh_key_path}" ]; then
    printf "    ssh_authorized_keys: []\n"
    return
  fi

  printf "    ssh_authorized_keys:\n"
  while IFS= read -r key; do
    printf "      - %s\n" "${key}"
  done <"${ssh_key_path}"
}

build_seed_iso() {
  rm -f "${seed_iso}"
  hdiutil makehybrid \
    -iso \
    -joliet \
    -default-volume-name cidata \
    -o "${seed_iso}" \
    "${seed_dir}" >/dev/null
}

print_result() {
  printf "cloud-init seed is ready:\n"
  printf "  %s\n" "${seed_iso}"
  printf "  user: %s\n" "${username}"
  printf "  password: %s\n" "${password}"
  printf "  hostname: %s\n" "${hostname}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1
}

fail() {
  printf "error: %s\n" "$1" >&2
  exit 1
}

main "$@"
