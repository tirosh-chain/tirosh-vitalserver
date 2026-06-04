#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
generated_uninstall="${script_dir}/uninstall"
installed_uninstall="${VITALSERVER_UNINSTALLER:-/usr/local/bin/tirosh-vitalserver-uninstall}"

if [ -x "${generated_uninstall}" ]; then
  exec "${generated_uninstall}" "$@"
fi

exec "${installed_uninstall}" "$@"
