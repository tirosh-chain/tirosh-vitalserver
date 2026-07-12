#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "VitalServer Linux rollback requires root." >&2
  exit 1
fi

for command in flock python3 readlink ln mv systemctl curl sync cp rm; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "VitalServer Linux rollback dependency is unavailable: $command" >&2
    exit 1
  fi
done

exec 9>/var/lock/vitalserver-linux-install.lock
if ! flock -n 9; then
  echo "Another VitalServer Linux install, update, or rollback is active." >&2
  exit 1
fi

opt_root=/opt/vitalserver
var_root=/var/lib/vitalserver
etc_root=/etc/vitalserver
unit_root=/etc/systemd/system
release_systemd_snapshot_root=$etc_root/release-systemd-units
current_link=$opt_root/current
install_document=$var_root/install.json
token_path=/etc/vitalserver/secrets/platform-api-token
install_document_backup=$var_root/.install.rollback.$$.json

if [ ! -L "$current_link" ]; then
  echo "VitalServer current release owner symlink is missing: $current_link" >&2
  exit 1
fi
if [ ! -s "$install_document" ]; then
  echo "VitalServer install owner document is missing or empty: $install_document" >&2
  exit 1
fi

previous_target=$(python3 - "$install_document" <<'PY'
import json, re, sys
path = sys.argv[1]
try:
    document = json.load(open(path, encoding="utf-8"))
except Exception as error:
    raise SystemExit(f"install owner decode failed path={path}: {error}")
if document.get("schemaVersion") != 1 or document.get("state") != "installed":
    raise SystemExit(f"install owner contract is invalid path={path}")
target = document.get("previousRelease")
if not isinstance(target, str) or not re.fullmatch(r"releases/[A-Za-z0-9._+-]+", target):
    raise SystemExit("install owner has no valid previousRelease")
print(target)
PY
)
current_target=$(readlink "$current_link")

validate_release_target() {
  release=$1
  case "$release" in
    releases/*)
      release_version=${release#releases/}
      ;;
    *)
      echo "VitalServer rollback release target is invalid: $release" >&2
      return 1
      ;;
  esac
  case "$release_version" in
    ""|*/*|*[!A-Za-z0-9._+-]*)
      echo "VitalServer rollback release target is invalid: $release" >&2
      return 1
      ;;
  esac
}

require_release_unit_directory() {
  directory=$1
  label=$2
  if [ ! -d "$directory" ] || [ -L "$directory" ]; then
    echo "VitalServer rollback $label is not a directory: $directory" >&2
    return 1
  fi
  for unit in \
    vitalserver-platform-agent.service \
    vitalserver-runtime-controller.service \
    vitalserver-runtime-provider.service; do
    if [ ! -f "$directory/$unit" ] || [ -L "$directory/$unit" ]; then
      echo "VitalServer rollback $label is incomplete: $directory/$unit" >&2
      return 1
    fi
  done
}

resolve_release_unit_directory() {
  release=$1
  bundled_units="$opt_root/$release/tools/systemd"
  if [ -e "$bundled_units" ] || [ -L "$bundled_units" ]; then
    if ! require_release_unit_directory "$bundled_units" "bundled release systemd units"; then
      return 1
    fi
    printf '%s\n' "$bundled_units"
    return
  fi

  migration_snapshot="$release_systemd_snapshot_root/$release"
  if [ -e "$migration_snapshot" ] || [ -L "$migration_snapshot" ]; then
    if ! require_release_unit_directory \
      "$migration_snapshot" "release systemd migration snapshot"; then
      return 1
    fi
    printf '%s\n' "$migration_snapshot"
    return
  fi
  echo "VitalServer rollback release systemd unit source is unavailable: release=$release bundled=$bundled_units migrationSnapshot=$migration_snapshot" >&2
  return 1
}

if ! validate_release_target "$current_target"; then
  exit 1
fi
if [ "$previous_target" = "$current_target" ]; then
  echo "VitalServer rollback target is already current: $previous_target" >&2
  exit 1
fi
if [ ! -f "$opt_root/$previous_target/release.json" ]; then
  echo "VitalServer rollback release is missing: $opt_root/$previous_target" >&2
  exit 1
fi
if [ ! -x "$opt_root/$previous_target/tools/acceptance-linux.py" ]; then
  echo "VitalServer rollback acceptance tool is missing: $opt_root/$previous_target/tools/acceptance-linux.py" >&2
  exit 1
fi
restore_release_units() {
  release=$1
  source_directory=$2
  for unit in \
    vitalserver-platform-agent.service \
    vitalserver-runtime-controller.service \
    vitalserver-runtime-provider.service; do
    if ! cp "$source_directory/$unit" "$unit_root/$unit"; then
      echo "VitalServer rollback systemd unit restoration failed release=$release source=$source_directory unit=$unit" >&2
      return 1
    fi
  done
}

if ! current_unit_source=$(resolve_release_unit_directory "$current_target"); then
  exit 1
fi
if ! previous_unit_source=$(resolve_release_unit_directory "$previous_target"); then
  exit 1
fi
cp "$install_document" "$install_document_backup"
chmod 0600 "$install_document_backup"

restore_current() {
  status=${1:-$?}
  trap - EXIT HUP INT TERM
  restore_failed=0
  release_restored=1
  document_restored=1
  units_restored=1
  if ! ln -s "$current_target" "$current_link.restore.$$" || \
    ! mv -Tf "$current_link.restore.$$" "$current_link"; then
    echo "VitalServer Linux rollback original release restoration failed target=$current_target" >&2
    release_restored=0
    restore_failed=1
  fi
  if [ -f "$install_document_backup" ]; then
    if ! mv -f "$install_document_backup" "$install_document"; then
      echo "VitalServer Linux rollback install owner restoration failed path=$install_document" >&2
      document_restored=0
      restore_failed=1
    fi
  else
    echo "VitalServer Linux rollback install owner backup is missing path=$install_document_backup" >&2
    document_restored=0
    restore_failed=1
  fi
  if ! restore_release_units "$current_target" "$current_unit_source"; then
    units_restored=0
    restore_failed=1
  fi
  if [ "$release_restored" -eq 1 ] && [ "$document_restored" -eq 1 ] && \
    [ "$units_restored" -eq 1 ]; then
    if ! systemctl daemon-reload; then
      echo "VitalServer Linux rollback original systemd reload failed" >&2
      restore_failed=1
    elif ! systemctl restart vitalserver-runtime-provider.service; then
      echo "VitalServer Linux rollback original Runtime Provider restart failed" >&2
      restore_failed=1
    elif ! systemctl restart vitalserver-runtime-controller.service; then
      echo "VitalServer Linux rollback original Runtime Controller restart failed" >&2
      restore_failed=1
    elif ! systemctl restart vitalserver-platform-agent.service; then
      echo "VitalServer Linux rollback original Platform Agent restart failed" >&2
      restore_failed=1
    fi
  else
    echo "VitalServer Linux rollback original service restart skipped because restoration is incomplete" >&2
  fi
  if [ "$restore_failed" -eq 0 ]; then
    restore_state=restored
  else
    restore_state=failed
  fi
  echo "VitalServer Linux rollback failed; original release restoreState=$restore_state target=$current_target" >&2
  if [ "$status" -eq 0 ]; then
    exit 1
  fi
  exit "$status"
}
trap restore_current EXIT
trap 'restore_current 129' HUP
trap 'restore_current 130' INT
trap 'restore_current 143' TERM

ln -s "$previous_target" "$current_link.rollback.$$"
mv -Tf "$current_link.rollback.$$" "$current_link"
restore_release_units "$previous_target" "$previous_unit_source"
systemctl daemon-reload
systemctl restart vitalserver-runtime-provider.service
systemctl restart vitalserver-runtime-controller.service
systemctl restart vitalserver-platform-agent.service

python3 "$opt_root/$previous_target/tools/acceptance-linux.py" \
  --api-token-path "$token_path" \
  --runtime-provider-document "$var_root/run/runtime-provider.json" \
  --output-manifest "$var_root/proof/linux-native-rollback-acceptance.json" \
  --base-url http://127.0.0.1:18321 \
  --timeout-seconds 180 \
  --support-export-mode capability-only

python3 - "$opt_root/$previous_target/release.json" "$install_document" "$current_target" <<'PY'
import json, os, sys, tempfile
from datetime import UTC, datetime
release_path, install_path, previous_release = sys.argv[1:]
release = json.load(open(release_path, encoding="utf-8"))
platform_version = release.get("platformVersion")
runtime_version = release.get("runtimeBundleVersion")
if not isinstance(platform_version, str) or not platform_version:
    raise SystemExit(f"rollback release platformVersion is invalid: {release_path}")
if not isinstance(runtime_version, str) or not runtime_version:
    raise SystemExit(f"rollback release runtimeBundleVersion is invalid: {release_path}")
document = {
    "schemaVersion": 1,
    "state": "installed",
    "platformVersion": platform_version,
    "runtimeBundleVersion": runtime_version,
    "installedAcceptanceRunId": json.load(open("/var/lib/vitalserver/proof/linux-native-rollback-acceptance.json", encoding="utf-8"))["runId"],
    "installedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    "installedBootId": open("/proc/sys/kernel/random/boot_id", encoding="utf-8").read().strip(),
    "previousRelease": previous_release,
}
directory = os.path.dirname(install_path)
descriptor, temporary = tempfile.mkstemp(dir=directory, prefix=".install.json.", suffix=".tmp")
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(document, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, install_path)
except Exception:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY
sync "$install_document"
rm -f "$install_document_backup"

trap - EXIT HUP INT TERM
echo "VitalServer Linux rollback passed release=$previous_target previousRelease=$current_target"
