#!/usr/bin/env bash
set -euo pipefail

main() {
  load_config
  resolve_paths
  resolve_asset_names
  require_tools
  prepare_directories
  download_assets
  install_boot_assets
  print_result
}

load_config() {
  config_file="${VM_UBUNTU_CONFIG:-$(script_dir)/ubuntu-cloud-image.env}"
  if [ ! -f "${config_file}" ]; then
    fail "missing Ubuntu image config: ${config_file}"
  fi

  # shellcheck disable=SC1090
  . "${config_file}"

  ubuntu_version="${VM_UBUNTU_VERSION:?missing VM_UBUNTU_VERSION in ${config_file}}"
  base_url="${VM_UBUNTU_BASE_URL:?missing VM_UBUNTU_BASE_URL in ${config_file}}"
  requested_arch="${VM_UBUNTU_ARCH:-auto}"
  kernel_suffix="${VM_UBUNTU_KERNEL_SUFFIX:-vmlinuz-generic}"
  initrd_suffix="${VM_UBUNTU_INITRD_SUFFIX:-initrd-generic}"
}

resolve_paths() {
  images_dir="${VM_IMAGE_DIR:-${VM_HOME:-${HOME}/.tirosh/vitalserver-vm}/images}"
  download_dir="${images_dir}/downloads"
}

resolve_asset_names() {
  arch="$(resolve_arch "${requested_arch}")"
  asset_prefix="ubuntu-${ubuntu_version}-server-cloudimg-${arch}"

  kernel_name="${asset_prefix}-${kernel_suffix}"
  initrd_name="${asset_prefix}-${initrd_suffix}"
  image_name="${asset_prefix}.img"

  kernel_url="${base_url}/unpacked/${kernel_name}"
  initrd_url="${base_url}/unpacked/${initrd_name}"
  image_url="${base_url}/${image_name}"
}

resolve_arch() {
  requested="$1"
  if [ "${requested}" != "auto" ]; then
    printf "%s" "${requested}"
    return
  fi

  case "$(uname -m)" in
    arm64 | aarch64)
      printf "arm64"
      ;;
    x86_64 | amd64)
      printf "amd64"
      ;;
    *)
      fail "unsupported host architecture: $(uname -m)"
      ;;
  esac
}

require_tools() {
  require_command curl
  require_command qemu-img \
    || fail "missing qemu-img. Install it on the build machine with: brew install qemu"
}

prepare_directories() {
  mkdir -p "${images_dir}" "${download_dir}"
}

download_assets() {
  printf "Ubuntu image config: %s\n" "${config_file}"
  printf "Ubuntu image arch: %s\n" "${arch}"

  download_once "${kernel_url}" "${download_dir}/${kernel_name}"
  download_once "${initrd_url}" "${download_dir}/${initrd_name}"
  download_once "${image_url}" "${download_dir}/${image_name}"
}

install_boot_assets() {
  cp "${download_dir}/${kernel_name}" "${images_dir}/vmlinuz"
  cp "${download_dir}/${initrd_name}" "${images_dir}/initrd.img"

  if [ -s "${images_dir}/rootfs.raw" ]; then
    printf "exists %s\n" "${images_dir}/rootfs.raw"
    return
  fi

  printf "converting %s to rootfs.raw\n" "${download_dir}/${image_name}"
  qemu-img convert -p -O raw "${download_dir}/${image_name}" "${images_dir}/rootfs.raw"
}

download_once() {
  url="$1"
  output="$2"
  partial="${output}.partial"

  if [ -s "${output}" ]; then
    printf "exists %s\n" "${output}"
    return
  fi

  printf "downloading %s\n" "${url}"
  curl --fail --location --continue-at - --output "${partial}" "${url}"
  mv "${partial}" "${output}"
}

print_result() {
  printf "Linux boot assets are ready:\n"
  printf "  %s\n" "${images_dir}/vmlinuz"
  printf "  %s\n" "${images_dir}/initrd.img"
  printf "  %s\n" "${images_dir}/rootfs.raw"
}

require_command() {
  command -v "$1" >/dev/null 2>&1
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

fail() {
  printf "error: %s\n" "$1" >&2
  exit 1
}

main "$@"
