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
  instance_id="${VM_CLOUD_INIT_INSTANCE_ID:-$(generate_instance_id)}"
  username="${VM_CLOUD_INIT_USER:-ubuntu}"
  password="${VM_CLOUD_INIT_PASSWORD:-ubuntu}"
  ssh_key_path="${VM_CLOUD_INIT_SSH_KEY:-${HOME}/.ssh/id_ed25519.pub}"
  run_bootstrap="${VM_CLOUD_INIT_RUN_BOOTSTRAP:-true}"
  share_tag="${VM_CLOUD_INIT_SHARE_TAG:-tirosh}"
  share_mount="${VM_CLOUD_INIT_SHARE_MOUNT:-/mnt/tirosh}"
  bootstrap_script="${VM_CLOUD_INIT_BOOTSTRAP_SCRIPT:-${share_mount}/deploy/bootstrap.sh}"
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
instance-id: ${instance_id}
local-hostname: ${hostname}
EOF
}

generate_instance_id() {
  if require_command uuidgen; then
    printf "tirosh-%s\n" "$(uuidgen | tr '[:upper:]' '[:lower:]')"
    return
  fi

  printf "tirosh-%s\n" "$(date +%s)"
}

write_user_data() {
  ssh_keys="$(cloud_init_ssh_keys)"
  bootstrap_commands="$(cloud_init_bootstrap_commands)"

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
${bootstrap_commands}
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

cloud_init_bootstrap_commands() {
  if [ "${run_bootstrap}" != "true" ]; then
    return
  fi

  cat <<EOF
runcmd:
  - mkdir -p ${share_mount}
  - mountpoint -q ${share_mount} || mount -t virtiofs ${share_tag} ${share_mount}
  - test -x ${bootstrap_script}
  - ${bootstrap_script}
EOF
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
  printf "  instance-id: %s\n" "${instance_id}"
  printf "  auto bootstrap: %s\n" "${run_bootstrap}"
  if [ "${run_bootstrap}" = "true" ]; then
    printf "  bootstrap script: %s\n" "${bootstrap_script}"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1
}

fail() {
  printf "error: %s\n" "$1" >&2
  exit 1
}

main "$@"
