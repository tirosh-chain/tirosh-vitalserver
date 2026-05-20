#!/usr/bin/env bash
set -euo pipefail

main() {
  resolve_settings "$@"
  prepare_bundle
  copy_nginx
  copy_dylibs
  rewrite_load_paths
  sign_bundle
  print_result
}

resolve_settings() {
  source_nginx="${1:-${NGINX_BIN:-nginx}}"
  bundle_dir="${2:?usage: bundle-nginx.sh <nginx-bin> <bundle-dir>}"

  if ! command -v "${source_nginx}" >/dev/null 2>&1 && [ ! -x "${source_nginx}" ]; then
    fail "nginx binary not found: ${source_nginx}"
  fi

  source_nginx="$(resolve_binary "${source_nginx}")"
  bundle_sbin="${bundle_dir}/sbin"
  bundle_lib="${bundle_dir}/lib"
  bundled_nginx="${bundle_sbin}/nginx"
}

prepare_bundle() {
  rm -rf "${bundle_dir}"
  mkdir -p "${bundle_sbin}" "${bundle_lib}" "${bundle_dir}/logs"
}

copy_nginx() {
  cp "${source_nginx}" "${bundled_nginx}"
  chmod 0755 "${bundled_nginx}"
}

copy_dylibs() {
  while IFS= read -r dylib; do
    cp "${dylib}" "${bundle_lib}/$(basename "${dylib}")"
    chmod 0644 "${bundle_lib}/$(basename "${dylib}")"
  done < <(non_system_dylibs "${source_nginx}")
}

rewrite_load_paths() {
  while IFS= read -r dylib; do
    name="$(basename "${dylib}")"
    bundled_dylib="${bundle_lib}/${name}"

    install_name_tool -id "@executable_path/../lib/${name}" "${bundled_dylib}"
    install_name_tool -change "${dylib}" "@executable_path/../lib/${name}" "${bundled_nginx}" || true

    while IFS= read -r nested; do
      nested_name="$(basename "${nested}")"
      install_name_tool -change "${nested}" "@executable_path/../lib/${nested_name}" "${bundled_dylib}" || true
    done < <(non_system_dylibs "${bundled_dylib}")
  done < <(non_system_dylibs "${source_nginx}")
}

sign_bundle() {
  codesign --force --sign - "${bundled_nginx}" >/dev/null

  while IFS= read -r dylib; do
    codesign --force --sign - "${dylib}" >/dev/null
  done < <(find "${bundle_lib}" -type f -name '*.dylib' | sort)
}

print_result() {
  printf "nginx bundle is ready:\n"
  printf "  %s\n" "${bundle_dir}"
  otool -L "${bundled_nginx}" | sed 's/^/  /'
}

non_system_dylibs() {
  otool -L "$1" \
    | awk 'NR > 1 {print $1}' \
    | grep -E '^/(opt|usr/local)/' \
    | sort -u
}

resolve_binary() {
  if [ -x "$1" ]; then
    cd "$(dirname "$1")"
    realpath "$(basename "$1")"
    return
  fi

  command -v "$1"
}

fail() {
  printf "error: %s\n" "$1" >&2
  exit 1
}

main "$@"
