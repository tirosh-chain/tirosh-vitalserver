#!/bin/sh
set -eu

acceptance_support_export_mode="execute"
if [ "$#" -ne 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--acceptance-support-export-mode" ]; then
    echo "Usage: install.sh [--acceptance-support-export-mode execute|capability-only]" >&2
    exit 2
  fi
  acceptance_support_export_mode=$2
fi
case "$acceptance_support_export_mode" in
  execute|capability-only) ;;
  *)
    echo "Acceptance support export mode is invalid: $acceptance_support_export_mode" >&2
    exit 2
    ;;
esac

bundle_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$(id -u)" -ne 0 ]; then
  echo "VitalServer Linux install requires root." >&2
  exit 1
fi

for command in sha256sum docker systemctl systemd-run install cp cmp mv ln od tr curl flock python3 sync cat stat readlink; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "VitalServer Linux install dependency is unavailable: $command" >&2
    exit 1
  fi
done

install -d -m 0755 /var/lock
exec 9>/var/lock/vitalserver-linux-install.lock
if ! flock -n 9; then
  echo "Another VitalServer Linux install or update is active." >&2
  exit 1
fi

cd "$bundle_dir"
sha256sum --check checksums.sha256

version=$(tr -d '\r\n' < VERSION)
runtime_bundle_version=$(tr -d '\r\n' < RUNTIME_BUNDLE_VERSION)
case "$version" in
  ""|*[!A-Za-z0-9._+-]*)
    echo "Platform artifact version is invalid: $version" >&2
    exit 1
    ;;
esac
case "$runtime_bundle_version" in
  ""|*[!A-Za-z0-9._+-]*)
    echo "Runtime Bundle version is invalid: $runtime_bundle_version" >&2
    exit 1
    ;;
esac

opt_root="/opt/vitalserver"
etc_root="/etc/vitalserver"
var_root="/var/lib/vitalserver"
unit_root="/etc/systemd/system"
release_root="$opt_root/releases/$version"
staging_root="$opt_root/releases/.${version}.installing.$$"
current_link="$opt_root/current"
release_completion_root="$etc_root/release-complete"
release_completion_document="$release_completion_root/$version.json"
install_transaction_document="$etc_root/install-transaction.json"
release_identity_line=$(sha256sum release.json)
release_identity_sha256=${release_identity_line%% *}
current_target=""
previous_target=""
install_transaction_active=0
install_transaction_previous_target=""
install_transaction_preserve_for_retry=0
release_root_exists=0
release_is_complete=0
release_systemd_snapshot_root="$etc_root/release-systemd-units"
release_systemd_snapshot_created=0
release_systemd_snapshot_path=""
release_systemd_snapshot_temporary=""
units_installed=0
services_enabled=0
configuration_created=0
runtime_settings_created=0
redis_relay_configuration_created=0
platform_agent_configuration_created=0
platform_agent_configuration_backed_up=0
native_provider_configuration_created=0
runtime_controller_configuration_created=0
runtime_environment_backed_up=0
units_backed_up=0
release_created=0
platform_agent_configuration_backup="$etc_root/.platform-agent.json.rollback.$$"
runtime_environment_backup="$etc_root/.runtime.env.rollback.$$"
platform_agent_unit_backup="$unit_root/.vitalserver-platform-agent.service.rollback.$$"
runtime_controller_unit_backup="$unit_root/.vitalserver-runtime-controller.service.rollback.$$"
runtime_provider_unit_backup="$unit_root/.vitalserver-runtime-provider.service.rollback.$$"

validate_release_target() {
  release=$1
  case "$release" in
    releases/*)
      release_version=${release#releases/}
      ;;
    *)
      echo "Linux release target is invalid: $release" >&2
      return 1
      ;;
  esac
  case "$release_version" in
    ""|*/*|*[!A-Za-z0-9._+-]*)
      echo "Linux release target is invalid: $release" >&2
      return 1
      ;;
  esac
}

require_root_owned_nonwritable_path() {
  path=$1
  label=$2
  kind=$3
  case "$kind" in
    file)
      if [ ! -f "$path" ] || [ -L "$path" ]; then
        echo "$label is missing or not a regular file: $path" >&2
        return 1
      fi
      ;;
    directory)
      if [ ! -d "$path" ] || [ -L "$path" ]; then
        echo "$label is missing or not a directory: $path" >&2
        return 1
      fi
      ;;
    *)
      echo "Linux install ownership contract kind is invalid: $kind" >&2
      return 1
      ;;
  esac
  owner=$(stat -c '%u' "$path") || {
    echo "$label ownership cannot be read: $path" >&2
    return 1
  }
  if [ "$owner" != "0" ]; then
    echo "$label must be root-owned: path=$path owner=$owner" >&2
    return 1
  fi
  mode=$(stat -c '%a' "$path") || {
    echo "$label permissions cannot be read: $path" >&2
    return 1
  }
  case "$mode" in
    ""|*[!0-7]*)
      echo "$label permissions are invalid: path=$path mode=$mode" >&2
      return 1
      ;;
  esac
  if [ $((0$mode & 022)) -ne 0 ]; then
    echo "$label must not be group- or world-writable: path=$path mode=$mode" >&2
    return 1
  fi
}

require_root_owned_regular_file() {
  require_root_owned_nonwritable_path "$1" "$2" file
}

require_root_owned_nonwritable_directory() {
  require_root_owned_nonwritable_path "$1" "$2" directory
}

ensure_root_owned_nonwritable_directory() {
  path=$1
  label=$2
  mode=$3
  if [ -e "$path" ] || [ -L "$path" ]; then
    require_root_owned_nonwritable_directory "$path" "$label"
    return
  fi
  if ! install -d -m "$mode" "$path"; then
    echo "$label creation failed: $path" >&2
    return 1
  fi
  require_root_owned_nonwritable_directory "$path" "$label"
}

sync_directory() {
  directory=$1
  python3 - "$directory" <<'PY'
import os
import sys

path = sys.argv[1]
try:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
except OSError as error:
    raise SystemExit(f"Linux installer directory durability open failed: {path}: {error}")
try:
    os.fsync(descriptor)
except OSError as error:
    raise SystemExit(f"Linux installer directory durability sync failed: {path}: {error}")
finally:
    os.close(descriptor)
PY
}

ensure_release_completion_root() {
  if [ -e "$release_completion_root" ]; then
    require_root_owned_nonwritable_directory \
      "$release_completion_root" "Linux release completion root"
    return
  fi
  if ! install -d -m 0700 "$release_completion_root"; then
    echo "Linux release completion root creation failed: $release_completion_root" >&2
    return 1
  fi
  require_root_owned_nonwritable_directory \
    "$release_completion_root" "Linux release completion root"
}

require_release_root_identity() {
  if ! require_root_owned_nonwritable_directory \
    "$release_root" "Installed Linux release"; then
    return 1
  fi
  if ! require_root_owned_regular_file \
    "$release_root/release.json" "Installed Linux release identity"; then
    return 1
  fi
  if ! cmp -s release.json "$release_root/release.json"; then
    echo "Installed release version already exists with different identity: $release_root" >&2
    return 1
  fi
}

require_release_completion_proof() {
  if ! require_root_owned_regular_file \
    "$release_completion_document" "Linux release completion proof"; then
    return 1
  fi
  python3 - "$release_completion_document" "$version" \
    "$runtime_bundle_version" "$release_identity_sha256" <<'PY'
import json
import sys

path, version, runtime_bundle_version, release_sha256 = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as stream:
        document = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"Linux release completion proof is invalid: {path}: {error}")

expected = {
    "schemaVersion": 1,
    "state": "complete",
    "platformVersion": version,
    "runtimeBundleVersion": runtime_bundle_version,
    "releaseSHA256": release_sha256,
}
if document != expected:
    raise SystemExit(
        f"Linux release completion proof does not match the requested bundle: {path}"
    )
PY
}

write_release_completion_proof() {
  if ! ensure_release_completion_root; then
    return 1
  fi
  temporary="$release_completion_root/.${version}.complete.$$"
  cat >"$temporary" <<EOF
{
  "schemaVersion": 1,
  "state": "complete",
  "platformVersion": "$version",
  "runtimeBundleVersion": "$runtime_bundle_version",
  "releaseSHA256": "$release_identity_sha256"
}
EOF
  if ! chmod 0600 "$temporary" || ! sync "$temporary" || \
    ! mv -f "$temporary" "$release_completion_document"; then
    rm -f "$temporary"
    echo "Linux release completion proof publish failed: $release_completion_document" >&2
    return 1
  fi
  if ! sync_directory "$release_completion_root"; then
    echo "Linux release completion proof directory durability failed: $release_completion_root" >&2
    return 1
  fi
}

read_installed_owner_previous_release() {
  if ! require_root_owned_nonwritable_directory \
    "$var_root" "Linux install owner root"; then
    return 1
  fi
  if ! require_root_owned_regular_file \
    "$var_root/install.json" "Linux install owner"; then
    return 1
  fi
  python3 - "$var_root/install.json" "$version" "$runtime_bundle_version" <<'PY'
import json
import re
import sys

path, version, runtime_bundle_version = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as stream:
        document = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"Linux install owner is unavailable or invalid: {error}")

if document.get("schemaVersion") != 1:
    raise SystemExit("Linux install owner schemaVersion is invalid")
if document.get("state") != "installed" or document.get("platformVersion") != version:
    raise SystemExit("Linux install owner identity does not match the current release")
if document.get("runtimeBundleVersion") != runtime_bundle_version:
    raise SystemExit("Linux install owner runtime bundle does not match the current release")
if not isinstance(document.get("installedAcceptanceRunId"), str) or not document[
    "installedAcceptanceRunId"
]:
    raise SystemExit("Linux install owner acceptance proof is unavailable")

previous_release = document.get("previousRelease")
if previous_release is None:
    print("-")
elif not isinstance(previous_release, str) or not re.fullmatch(
    r"releases/[A-Za-z0-9._+-]+", previous_release
):
    raise SystemExit("Linux install owner has an invalid previousRelease")
elif previous_release == f"releases/{version}":
    raise SystemExit("Linux install owner previousRelease points to itself")
else:
    print(previous_release)
PY
}

finish_published_install_transaction() {
  candidate_target="releases/$version"
  if [ "$install_transaction_active" -eq 0 ] || \
    [ "$install_transaction_previous_target" = "$candidate_target" ] || \
    [ "$current_target" != "$candidate_target" ] || \
    [ "$release_is_complete" -eq 0 ]; then
    return 0
  fi
  if [ ! -e "$var_root/install.json" ] && [ ! -L "$var_root/install.json" ]; then
    return 0
  fi
  if ! require_root_owned_nonwritable_directory \
    "$var_root" "Linux install owner root" || \
    ! require_root_owned_regular_file \
      "$var_root/install.json" "Linux install owner"; then
    return 1
  fi
  expected_previous_release=$install_transaction_previous_target
  transaction_commit_state=$(python3 - "$var_root/install.json" "$version" \
    "$runtime_bundle_version" "$expected_previous_release" <<'PY'
import json
import re
import sys

path, version, runtime_bundle_version, expected_previous_release = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as stream:
        document = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"Linux install owner is unavailable or invalid: {error}")

if document.get("schemaVersion") != 1:
    raise SystemExit("Linux install owner schemaVersion is invalid")
if document.get("platformVersion") != version:
    print("pending")
    raise SystemExit(0)
if document.get("state") != "installed":
    raise SystemExit("Linux install owner state is invalid for the candidate release")
if document.get("runtimeBundleVersion") != runtime_bundle_version:
    raise SystemExit("Linux install owner runtime bundle does not match the candidate release")
if not isinstance(document.get("installedAcceptanceRunId"), str) or not document[
    "installedAcceptanceRunId"
]:
    raise SystemExit("Linux install owner acceptance proof is unavailable")

previous_release = document.get("previousRelease")
if previous_release is not None and (
    not isinstance(previous_release, str)
    or re.fullmatch(r"releases/[A-Za-z0-9._+-]+", previous_release) is None
):
    raise SystemExit("Linux install owner previousRelease is invalid")
expected = expected_previous_release or None
if previous_release != expected:
    raise SystemExit(
        "Linux install owner previousRelease does not match the active transaction"
    )
print("committed")
PY
  ) || return 1
  case "$transaction_commit_state" in
    pending)
      return 0
      ;;
    committed)
      if ! rm -f "$install_transaction_document"; then
        echo "Linux published install transaction cleanup failed: $install_transaction_document" >&2
        return 1
      fi
      if ! sync_directory "$etc_root"; then
        echo "Linux published install transaction directory durability failed: $etc_root" >&2
        return 1
      fi
      install_transaction_active=0
      install_transaction_preserve_for_retry=0
      previous_target=$current_target
      ;;
    *)
      echo "Linux install transaction completion state is invalid: $transaction_commit_state" >&2
      return 1
      ;;
  esac
}

read_install_transaction() {
  if [ ! -e "$install_transaction_document" ] && \
    [ ! -L "$install_transaction_document" ]; then
    return 0
  fi
  if ! require_root_owned_regular_file \
    "$install_transaction_document" "Linux install transaction"; then
    return 1
  fi
  transaction_values=$(python3 - "$install_transaction_document" <<'PY'
import json
import re
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as stream:
        document = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"Linux install transaction is unavailable or invalid: {error}")

version = document.get("platformVersion")
runtime_bundle_version = document.get("runtimeBundleVersion")
release_sha256 = document.get("releaseSHA256")
previous_release = document.get("previousRelease")
if document.get("schemaVersion") != 1 or document.get("state") != "installing":
    raise SystemExit("Linux install transaction contract is invalid")
if not isinstance(version, str) or not re.fullmatch(r"[A-Za-z0-9._+-]+", version):
    raise SystemExit("Linux install transaction platformVersion is invalid")
if not isinstance(runtime_bundle_version, str) or not re.fullmatch(
    r"[A-Za-z0-9._+-]+", runtime_bundle_version
):
    raise SystemExit("Linux install transaction runtimeBundleVersion is invalid")
if not isinstance(release_sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", release_sha256):
    raise SystemExit("Linux install transaction releaseSHA256 is invalid")
if previous_release is None:
    previous = "-"
elif isinstance(previous_release, str) and re.fullmatch(
    r"releases/[A-Za-z0-9._+-]+", previous_release
):
    previous = previous_release
else:
    raise SystemExit("Linux install transaction previousRelease is invalid")
print(":".join((version, runtime_bundle_version, release_sha256, previous)))
PY
  ) || return 1
  IFS=: read -r transaction_version transaction_runtime_bundle_version \
    transaction_release_sha256 transaction_previous_release <<EOF
$transaction_values
EOF
  if [ "$transaction_version" != "$version" ] || \
    [ "$transaction_runtime_bundle_version" != "$runtime_bundle_version" ] || \
    [ "$transaction_release_sha256" != "$release_identity_sha256" ]; then
    echo "Linux install transaction belongs to a different bundle: $install_transaction_document" >&2
    return 1
  fi
  if [ "$transaction_previous_release" = "-" ]; then
    install_transaction_previous_target=""
  else
    install_transaction_previous_target=$transaction_previous_release
  fi
  install_transaction_active=1
  # A transaction found before this process started can already own a mix of
  # live candidate and previous-release state.  A later failure in this
  # process must leave that evidence intact for the same verified bundle to
  # resume; it cannot safely reinterpret it as a fresh B -> C rollback.
  install_transaction_preserve_for_retry=1
}

begin_install_transaction() {
  previous_release=$1
  if [ -n "$previous_release" ]; then
    previous_release_document="\"$previous_release\""
  else
    previous_release_document="null"
  fi
  temporary="$etc_root/.install-transaction.json.$$"
  cat >"$temporary" <<EOF
{
  "schemaVersion": 1,
  "state": "installing",
  "platformVersion": "$version",
  "runtimeBundleVersion": "$runtime_bundle_version",
  "releaseSHA256": "$release_identity_sha256",
  "previousRelease": $previous_release_document
}
EOF
  if ! chmod 0600 "$temporary" || ! sync "$temporary" || \
    ! mv -f "$temporary" "$install_transaction_document"; then
    rm -f "$temporary"
    echo "Linux install transaction publish failed: $install_transaction_document" >&2
    return 1
  fi
  if ! sync_directory "$etc_root"; then
    echo "Linux install transaction directory durability failed: $etc_root" >&2
    return 1
  fi
  install_transaction_active=1
  install_transaction_previous_target=$previous_release
  install_transaction_preserve_for_retry=0
}

validate_install_transaction_current_target() {
  if [ "$install_transaction_active" -eq 0 ]; then
    return 0
  fi
  candidate_target="releases/$version"
  if [ "$current_target" = "$candidate_target" ]; then
    previous_target=$install_transaction_previous_target
    return 0
  fi
  if [ "$current_target" = "$install_transaction_previous_target" ]; then
    previous_target=$current_target
    return 0
  fi
  if [ -z "$current_target" ] && [ -z "$install_transaction_previous_target" ]; then
    previous_target=""
    return 0
  fi
  echo "Linux install transaction current release does not match its owner: current=${current_target:-none} previous=${install_transaction_previous_target:-none}" >&2
  return 1
}

require_systemd_unit_directory() {
  directory=$1
  label=$2
  if ! require_root_owned_nonwritable_directory "$directory" "$label"; then
    return 1
  fi
  for unit in \
    vitalserver-platform-agent.service \
    vitalserver-runtime-controller.service \
    vitalserver-runtime-provider.service; do
    if ! require_root_owned_regular_file "$directory/$unit" "$label unit"; then
      return 1
    fi
  done
}

ensure_release_systemd_snapshot_root() {
  for directory in \
    "$release_systemd_snapshot_root" \
    "$release_systemd_snapshot_root/releases"; do
    if [ -e "$directory" ]; then
      if [ ! -d "$directory" ] || [ -L "$directory" ]; then
        echo "Linux release systemd snapshot root is invalid: $directory" >&2
        return 1
      fi
      continue
    fi
    if ! install -d -m 0750 "$directory"; then
      echo "Linux release systemd snapshot root creation failed: $directory" >&2
      return 1
    fi
  done
}

snapshot_release_systemd_units() {
  release=$1
  if ! validate_release_target "$release"; then
    return 1
  fi
  bundled_units="$opt_root/$release/tools/systemd"
  if [ -e "$bundled_units" ] || [ -L "$bundled_units" ]; then
    if ! require_systemd_unit_directory \
      "$bundled_units" "Existing release systemd units"; then
      return 1
    fi
    return 0
  fi

  snapshot_root="$release_systemd_snapshot_root/$release"
  if [ -e "$snapshot_root" ] || [ -L "$snapshot_root" ]; then
    if ! require_systemd_unit_directory \
      "$snapshot_root" "Existing release systemd migration snapshot"; then
      return 1
    fi
    # A matching transaction may have already applied the candidate's units.
    # The root-owned snapshot is the immutable previous-release source, so it
    # must stay distinct from those live candidate units until the same bundle
    # finishes or an explicit rollback owns the restoration.
    if [ "$install_transaction_preserve_for_retry" -eq 1 ]; then
      return 0
    fi
    for unit in \
      vitalserver-platform-agent.service \
      vitalserver-runtime-controller.service \
      vitalserver-runtime-provider.service; do
      if ! cmp -s "$unit_root/$unit" "$snapshot_root/$unit"; then
        echo "Linux release systemd migration snapshot does not match the current unit: unit=$unit" >&2
        return 1
      fi
    done
    return 0
  fi

  if [ "$install_transaction_preserve_for_retry" -eq 1 ]; then
    echo "Linux release systemd migration snapshot is unavailable for resumed transaction: release=$release snapshot=$snapshot_root" >&2
    return 1
  fi

  if ! ensure_release_systemd_snapshot_root; then
    return 1
  fi
  temporary_snapshot="$release_systemd_snapshot_root/releases/.${release_version}.systemd.snapshot.$$"
  release_systemd_snapshot_temporary=$temporary_snapshot
  if ! install -d -m 0750 "$temporary_snapshot"; then
    echo "Linux release systemd snapshot migration directory creation failed: $temporary_snapshot" >&2
    return 1
  fi
  for unit in \
    vitalserver-platform-agent.service \
    vitalserver-runtime-controller.service \
    vitalserver-runtime-provider.service; do
    if [ ! -f "$unit_root/$unit" ] || [ -L "$unit_root/$unit" ]; then
      echo "Existing Linux systemd unit is missing: $unit_root/$unit" >&2
      return 1
    fi
    if ! install -m 0644 "$unit_root/$unit" "$temporary_snapshot/$unit"; then
      echo "Linux release systemd snapshot migration copy failed: unit=$unit" >&2
      return 1
    fi
  done
  if ! mv "$temporary_snapshot" "$snapshot_root"; then
    echo "Linux release systemd snapshot migration publish failed: $snapshot_root" >&2
    return 1
  fi
  release_systemd_snapshot_temporary=""
  release_systemd_snapshot_created=1
  release_systemd_snapshot_path=$snapshot_root
  if ! sync_directory "$release_systemd_snapshot_root/releases"; then
    echo "Linux release systemd snapshot migration directory durability failed: $release_systemd_snapshot_root/releases" >&2
    return 1
  fi
}

if ! ensure_root_owned_nonwritable_directory \
  "$opt_root" "Linux release root" 0755 || \
  ! ensure_root_owned_nonwritable_directory \
    "$opt_root/releases" "Linux releases root" 0755 || \
  ! ensure_root_owned_nonwritable_directory \
    "$var_root" "Linux install owner root" 0755; then
  exit 1
fi

if [ -L "$current_link" ]; then
  current_target=$(readlink "$current_link") || {
    echo "Linux current release owner cannot be read: $current_link" >&2
    exit 1
  }
elif [ -e "$current_link" ]; then
  echo "Linux current release owner is not a symbolic link: $current_link" >&2
  exit 1
fi
if [ -n "$current_target" ] && ! validate_release_target "$current_target"; then
  exit 1
fi
previous_target=$current_target

if ! install -d -m 0755 "$etc_root"; then
  echo "Linux install transaction root creation failed: $etc_root" >&2
  exit 1
fi
if ! require_root_owned_nonwritable_directory \
  "$etc_root" "Linux install transaction root"; then
  exit 1
fi
if ! read_install_transaction; then
  exit 1
fi
if ! validate_install_transaction_current_target; then
  exit 1
fi
if [ -n "$previous_target" ] && ! validate_release_target "$previous_target"; then
  exit 1
fi

if [ -e "$release_root" ] || [ -L "$release_root" ]; then
  if ! require_release_root_identity; then
    exit 1
  fi
  release_root_exists=1
  if [ -e "$release_completion_document" ] || \
    [ -L "$release_completion_document" ]; then
    if ! require_release_completion_proof; then
      exit 1
    fi
    release_is_complete=1
  elif [ "$install_transaction_active" -eq 1 ]; then
    # A matching, durable transaction is the only owner allowed to resume a
    # release that was published before its guest-tools install completed.
    release_is_complete=0
  elif [ "$current_target" = "releases/$version" ]; then
    # Explicit migration for installations created before completion receipts
    # existed.  A matching installed owner and acceptance proof, not
    # release.json alone, authorizes the root-owned receipt.
    if ! read_installed_owner_previous_release >/dev/null || \
      ! write_release_completion_proof; then
      exit 1
    fi
    release_is_complete=1
  else
    echo "Installed release is incomplete without a matching Linux install transaction: $release_root" >&2
    exit 1
  fi
fi
if ! finish_published_install_transaction; then
  exit 1
fi

require_previous_release_artifacts() {
  release=$1
  previous_release_directory="$opt_root/$release"
  if [ ! -d "$previous_release_directory" ] || [ -L "$previous_release_directory" ]; then
    echo "Existing Linux release is missing or invalid: $previous_release_directory" >&2
    return 1
  fi
  if [ ! -f "$previous_release_directory/release.json" ] || \
    [ -L "$previous_release_directory/release.json" ]; then
    echo "Existing Linux release identity is missing: $previous_release_directory/release.json" >&2
    return 1
  fi
  if [ ! -x "$previous_release_directory/tools/acceptance-linux.py" ] || \
    [ -L "$previous_release_directory/tools/acceptance-linux.py" ]; then
    echo "Existing Linux release rollback acceptance tool is missing: $previous_release_directory/tools/acceptance-linux.py" >&2
    return 1
  fi
}

if [ -n "$previous_target" ] && ! require_previous_release_artifacts "$previous_target"; then
  exit 1
fi

rollback_install() {
  status=${1:-$?}
  trap - EXIT HUP INT TERM
  if [ "$install_transaction_preserve_for_retry" -eq 1 ]; then
    # This process resumed an explicit, matching transaction.  Its mutable
    # owners can include state published by the interrupted process, so a
    # B -> C rollback would be an inference.  Leave every owner untouched for
    # the same verified bundle to resume from the transaction document.
    echo "VitalServer Linux install failed version=$version rollbackState=preserved-for-retry previousRelease=${previous_target:-none} transaction=$install_transaction_document" >&2
    exit "$status"
  fi
  rollback_failed=0
  release_restored=1
  owner_configuration_restored=1
  units_restored=1
  if ! rm -rf \
    "$staging_root" \
    "$current_link.next.$$" \
    "$var_root/.install.json.$$" \
    "$etc_root/.install-transaction.json.$$" \
    "$etc_root/.runtime-config.json.$$" \
    "$etc_root/.runtime.env.$$"; then
    echo "Linux install rollback cleanup failed staging=$staging_root" >&2
    rollback_failed=1
  fi
  if [ -n "$release_systemd_snapshot_temporary" ] && \
    ! rm -rf "$release_systemd_snapshot_temporary"; then
    echo "Linux install rollback systemd snapshot staging cleanup failed path=$release_systemd_snapshot_temporary" >&2
    rollback_failed=1
  fi
  if [ "$platform_agent_configuration_backed_up" -eq 1 ]; then
    if ! install -m 0600 "$platform_agent_configuration_backup" "$etc_root/platform-agent.json"; then
      echo "Linux install rollback Platform Agent configuration restoration failed" >&2
      owner_configuration_restored=0
      rollback_failed=1
    fi
  fi
  if [ "$runtime_environment_backed_up" -eq 1 ]; then
    if ! install -m 0600 "$runtime_environment_backup" "$etc_root/runtime.env"; then
      echo "Linux install rollback Runtime environment restoration failed" >&2
      owner_configuration_restored=0
      rollback_failed=1
    fi
  fi
  if [ "$units_backed_up" -eq 1 ]; then
    if ! install -m 0644 "$platform_agent_unit_backup" \
      "$unit_root/vitalserver-platform-agent.service" || \
      ! install -m 0644 "$runtime_controller_unit_backup" \
      "$unit_root/vitalserver-runtime-controller.service" || \
      ! install -m 0644 "$runtime_provider_unit_backup" \
      "$unit_root/vitalserver-runtime-provider.service"; then
      echo "Linux install rollback systemd unit restoration failed" >&2
      units_restored=0
      rollback_failed=1
    fi
  fi
  if [ -n "$previous_target" ]; then
    if ! ln -s "$previous_target" "$current_link.rollback.$$" || \
      ! mv -Tf "$current_link.rollback.$$" "$current_link" || \
      ! sync_directory "$opt_root"; then
      echo "Linux install rollback release restoration failed previousRelease=$previous_target" >&2
      release_restored=0
      rollback_failed=1
    fi
    if [ "$release_restored" -eq 1 ] && \
      [ "$owner_configuration_restored" -eq 1 ] && \
      [ "$units_restored" -eq 1 ]; then
      if ! systemctl daemon-reload; then
        echo "Linux install rollback systemd reload failed" >&2
        rollback_failed=1
      elif ! systemctl restart vitalserver-runtime-provider.service; then
        echo "Linux install rollback Runtime Provider restart failed" >&2
        rollback_failed=1
      elif ! systemctl restart vitalserver-runtime-controller.service; then
        echo "Linux install rollback Runtime Controller restart failed" >&2
        rollback_failed=1
      elif ! systemctl restart vitalserver-platform-agent.service; then
        echo "Linux install rollback Platform Agent restart failed" >&2
        rollback_failed=1
      fi
    else
      echo "Linux install rollback service restart skipped because owner restoration is incomplete" >&2
    fi
  else
    if [ "$units_installed" -eq 1 ]; then
      if ! systemctl stop vitalserver-platform-agent.service vitalserver-runtime-controller.service vitalserver-runtime-provider.service; then
        echo "Linux first-install rollback service stop failed" >&2
        rollback_failed=1
      fi
    fi
    if [ "$services_enabled" -eq 1 ]; then
      if ! systemctl disable vitalserver-platform-agent.service vitalserver-runtime-controller.service vitalserver-runtime-provider.service; then
        echo "Linux first-install rollback service disable failed" >&2
        rollback_failed=1
      fi
    fi
    if [ "$units_installed" -eq 1 ]; then
      if ! rm -f \
        "$unit_root/vitalserver-platform-agent.service" \
        "$unit_root/vitalserver-runtime-controller.service" \
        "$unit_root/vitalserver-runtime-provider.service"; then
        echo "Linux first-install rollback systemd unit cleanup failed" >&2
        rollback_failed=1
      fi
      if ! systemctl daemon-reload; then
        echo "Linux first-install rollback systemd reload failed" >&2
        rollback_failed=1
      fi
    fi
    if ! rm -f "$current_link"; then
      echo "Linux first-install rollback current release removal failed" >&2
      rollback_failed=1
    fi
    if ! rm -rf "$var_root/run" "$var_root/proof"; then
      echo "Linux first-install rollback ephemeral state cleanup failed" >&2
      rollback_failed=1
    fi
  fi
  if [ "$configuration_created" -eq 1 ]; then
    if ! rm -f \
      "$etc_root/runtime-config.json" \
      "$etc_root/runtime.env" \
      "$etc_root/secrets/admin-password" \
      "$etc_root/secrets/postgres-password"; then
      echo "Linux install rollback generated Runtime configuration cleanup failed" >&2
      rollback_failed=1
    fi
  fi
  if [ "$runtime_settings_created" -eq 1 ] && ! rm -f "$etc_root/runtime-settings.json"; then
    echo "Linux install rollback generated Runtime settings cleanup failed" >&2
    rollback_failed=1
  fi
  if [ "$redis_relay_configuration_created" -eq 1 ] && ! rm -f "$etc_root/redis-relay/redis-relay.toml"; then
    echo "Linux install rollback generated Redis Relay configuration cleanup failed" >&2
    rollback_failed=1
  fi
  if [ "$platform_agent_configuration_created" -eq 1 ] && ! rm -f \
    "$etc_root/platform-agent.json" "$etc_root/secrets/platform-api-token"; then
    echo "Linux install rollback generated Platform Agent configuration cleanup failed" >&2
    rollback_failed=1
  fi
  if [ "$native_provider_configuration_created" -eq 1 ] && ! rm -f "$etc_root/native-runtime-provider.json"; then
    echo "Linux install rollback generated Native Provider configuration cleanup failed" >&2
    rollback_failed=1
  fi
  if [ "$runtime_controller_configuration_created" -eq 1 ] && ! rm -f "$etc_root/runtime-controller.toml"; then
    echo "Linux install rollback generated Runtime Controller configuration cleanup failed" >&2
    rollback_failed=1
  fi
  if ! rm -f "$platform_agent_configuration_backup"; then
    echo "Linux install rollback Platform Agent configuration backup cleanup failed" >&2
    rollback_failed=1
  fi
  if ! rm -f "$runtime_environment_backup"; then
    echo "Linux install rollback Runtime environment backup cleanup failed" >&2
    rollback_failed=1
  fi
  if ! rm -f \
    "$platform_agent_unit_backup" \
    "$runtime_controller_unit_backup" \
    "$runtime_provider_unit_backup"; then
    echo "Linux install rollback systemd unit backup cleanup failed" >&2
    rollback_failed=1
  fi
  candidate_cleanup_required=0
  if [ "$release_created" -eq 1 ]; then
    candidate_cleanup_required=1
  elif [ "$install_transaction_active" -eq 1 ] && \
    [ "$release_root_exists" -eq 1 ] && \
    [ "$install_transaction_previous_target" != "releases/$version" ]; then
    candidate_cleanup_required=1
  fi
  if [ "$candidate_cleanup_required" -eq 1 ]; then
    if [ "$rollback_failed" -eq 0 ]; then
      if ! rm -f "$release_completion_document"; then
        echo "Linux install rollback created release completion cleanup failed path=$release_completion_document" >&2
        rollback_failed=1
      fi
      if ! rm -rf "$release_root"; then
        echo "Linux install rollback transaction release cleanup failed release=$release_root" >&2
        rollback_failed=1
      fi
    else
      echo "Linux install rollback preserves transaction release because restoration is incomplete release=$release_root" >&2
    fi
  fi
  if [ "$release_systemd_snapshot_created" -eq 1 ]; then
    if [ "$rollback_failed" -eq 0 ]; then
      if ! rm -rf "$release_systemd_snapshot_path"; then
        echo "Linux install rollback created systemd snapshot cleanup failed path=$release_systemd_snapshot_path" >&2
        rollback_failed=1
      fi
    else
      echo "Linux install rollback preserves systemd migration snapshot because restoration is incomplete path=$release_systemd_snapshot_path" >&2
    fi
  fi
  if [ "$install_transaction_active" -eq 1 ]; then
    if [ "$rollback_failed" -eq 0 ]; then
      if ! rm -f "$install_transaction_document"; then
        echo "Linux install rollback transaction cleanup failed path=$install_transaction_document" >&2
        rollback_failed=1
      else
        install_transaction_active=0
      fi
    else
      echo "Linux install rollback preserves transaction because restoration is incomplete path=$install_transaction_document" >&2
    fi
  fi
  if [ "$rollback_failed" -eq 0 ]; then
    rollback_state="restored"
  else
    rollback_state="failed"
  fi
  echo "VitalServer Linux install failed version=$version rollbackState=$rollback_state previousRelease=${previous_target:-none}" >&2
  exit "$status"
}
trap rollback_install EXIT
trap 'rollback_install 129' HUP
trap 'rollback_install 130' INT
trap 'rollback_install 143' TERM

if [ "$install_transaction_active" -eq 0 ] && \
  ! begin_install_transaction "$current_target"; then
  exit 1
fi

install -d -m 0755 "$etc_root" "$unit_root"
install -d -m 0700 "$etc_root/secrets" "$etc_root/secrets/redis-relay"
install -d -m 0750 "$etc_root/redis-relay"
install -d -m 0755 "$var_root/run" "$var_root/data/vital-files" "$var_root/proof"
install -d -m 0700 "$var_root/inbox"
install -d -m 0750 /var/log/vitalserver
install -d -m 0755 \
  "$var_root/data/recorder-ingress/raw" \
  "$var_root/data/recorder-ingress/recovery" \
  "$var_root/data/recorder-ingress/failures" \
  "$var_root/run/redis-relay-status"

runtime_config="$etc_root/runtime-config.json"
runtime_settings="$etc_root/runtime-settings.json"
runtime_environment="$etc_root/runtime.env"
admin_secret="$etc_root/secrets/admin-password"
postgres_secret="$etc_root/secrets/postgres-password"

if [ -e "$runtime_config" ] || [ -e "$runtime_environment" ] || \
  [ -e "$admin_secret" ] || [ -e "$postgres_secret" ]; then
  for required_owner in "$runtime_config" "$runtime_environment" "$admin_secret" "$postgres_secret"; do
    if [ ! -s "$required_owner" ]; then
      echo "Existing Linux Runtime configuration owner set is incomplete: $required_owner" >&2
      exit 1
    fi
  done
else
  configuration_created=1
  admin_password=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
  postgres_password=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
  printf '%s\n' "$admin_password" >"$admin_secret"
  printf '%s\n' "$postgres_password" >"$postgres_secret"
  chmod 0600 "$admin_secret" "$postgres_secret"
  runtime_config_temporary="$etc_root/.runtime-config.json.$$"
  cat >"$runtime_config_temporary" <<EOF
{
  "adminPassword": "$admin_password",
  "remoteConsoleURL": "",
  "vitalServerURL": "",
  "publicHost": "",
  "publicPort": 80,
  "redisHost": "redis",
  "redisPort": 6379,
  "redisUiPort": 18081,
  "swaggerUiPort": 18082,
  "trustProxy": true,
  "vitalFilesDirectory": "/var/lib/vitalserver/data/vital-files",
  "vitalserverHttpPort": 18080
}
EOF
  chmod 0600 "$runtime_config_temporary"
  sync "$runtime_config_temporary"
  mv -f "$runtime_config_temporary" "$runtime_config"
  runtime_environment_temporary="$etc_root/.runtime.env.$$"
  cat packaging/runtime.env >"$runtime_environment_temporary"
  printf 'VITALSERVER_ADMIN_PASSWORD=%s\n' "$admin_password" >>"$runtime_environment_temporary"
  printf 'VITALSERVER_POSTGRES_PASSWORD=%s\n' "$postgres_password" >>"$runtime_environment_temporary"
  chmod 0600 "$runtime_environment_temporary"
  sync "$runtime_environment_temporary"
  mv -f "$runtime_environment_temporary" "$runtime_environment"
fi

if [ "$configuration_created" -eq 0 ]; then
  install -m 0600 "$runtime_environment" "$runtime_environment_backup"
  runtime_environment_backed_up=1
  if ! python3 "$bundle_dir/packaging/migrate-runtime-env.py" \
    --path "$runtime_environment"; then
    echo "Linux Runtime environment transport migration failed; preserving the existing owner file." >&2
    exit 1
  fi
fi

if [ ! -f "$runtime_settings" ]; then
  runtime_settings_created=1
  install -m 0600 packaging/runtime-settings.json "$runtime_settings"
fi
if [ ! -f "$etc_root/redis-relay/redis-relay.toml" ]; then
  redis_relay_configuration_created=1
  install -m 0600 packaging/redis-relay.toml "$etc_root/redis-relay/redis-relay.toml"
fi
if [ ! -f "$etc_root/runtime-controller.toml" ]; then
  runtime_controller_configuration_created=1
  install -m 0644 packaging/runtime-controller.toml "$etc_root/runtime-controller.toml"
fi

if [ -n "$previous_target" ]; then
  if ! snapshot_release_systemd_units "$previous_target"; then
    exit 1
  fi
  for unit in \
    vitalserver-platform-agent.service \
    vitalserver-runtime-controller.service \
    vitalserver-runtime-provider.service; do
    if [ ! -f "$unit_root/$unit" ]; then
      echo "Existing Linux systemd unit is missing: $unit_root/$unit" >&2
      exit 1
    fi
  done
  install -m 0644 "$unit_root/vitalserver-platform-agent.service" \
    "$platform_agent_unit_backup"
  install -m 0644 "$unit_root/vitalserver-runtime-controller.service" \
    "$runtime_controller_unit_backup"
  install -m 0644 "$unit_root/vitalserver-runtime-provider.service" \
    "$runtime_provider_unit_backup"
  units_backed_up=1
fi

rm -rf "$staging_root"
install -d -m 0755 "$staging_root"
cp -a bin pwa runtime-bundle runtime-controller "$staging_root/"
install -d -m 0755 "$staging_root/tools"
install -d -m 0755 "$staging_root/tools/systemd"
install -m 0755 packaging/acceptance-linux.py "$staging_root/tools/acceptance-linux.py"
install -m 0755 packaging/acceptance-reboot-linux.py "$staging_root/tools/acceptance-reboot-linux.py"
install -m 0755 packaging/acceptance-update-rollback-linux.py "$staging_root/tools/acceptance-update-rollback-linux.py"
install -m 0755 packaging/acceptance-uninstall-reinstall-linux.py "$staging_root/tools/acceptance-uninstall-reinstall-linux.py"
install -m 0755 packaging/rollback-linux.sh "$staging_root/tools/rollback-linux.sh"
install -m 0755 packaging/rollback-linux.py "$staging_root/tools/rollback-linux.py"
install -m 0755 packaging/update-linux.py "$staging_root/tools/update-linux.py"
install -m 0755 packaging/uninstall-linux.py "$staging_root/tools/uninstall-linux.py"
install -m 0755 packaging/support-export-linux.py "$staging_root/tools/support-export-linux.py"
install -m 0755 packaging/trust-update-linux.py "$staging_root/tools/trust-update-linux.py"
install -m 0644 packaging/vitalserver-platform-agent.service \
  "$staging_root/tools/systemd/vitalserver-platform-agent.service"
install -m 0644 packaging/vitalserver-runtime-controller.service \
  "$staging_root/tools/systemd/vitalserver-runtime-controller.service"
install -m 0644 packaging/vitalserver-runtime-provider.service \
  "$staging_root/tools/systemd/vitalserver-runtime-provider.service"
install -m 0644 release.json "$staging_root/release.json"

install_release_guest_tools() {
  VITALSERVER_RUNTIME_CONTROLLER_SETTINGS_PATH="$etc_root/runtime-controller.toml" \
    python3 "$release_root/runtime-controller/install-guest-tools-runtime.py" \
      --wheel-dir "$release_root/runtime-controller/python-wheels" \
      --guest-tools-home "$release_root/runtime-controller"
}

if [ "$release_root_exists" -eq 1 ]; then
  rm -rf "$staging_root"
  if [ "$release_is_complete" -eq 0 ]; then
    if ! install_release_guest_tools; then
      echo "Linux interrupted release guest-tools installation recovery failed: $release_root" >&2
      exit 1
    fi
    if ! write_release_completion_proof; then
      exit 1
    fi
    release_is_complete=1
  fi
else
  if ! mv "$staging_root" "$release_root"; then
    echo "Linux release publish failed: $release_root" >&2
    exit 1
  fi
  release_created=1
  if ! sync_directory "$opt_root/releases"; then
    echo "Linux release publish directory durability failed: $opt_root/releases" >&2
    exit 1
  fi
  # A venv embeds absolute interpreter paths in its console scripts.  Build it
  # only after the immutable release tree has its final pathname; building it
  # under staging_root would leave the Runtime Controller with a broken shebang
  # as soon as this directory is published.
  if ! install_release_guest_tools; then
    echo "Linux release guest-tools installation failed: $release_root" >&2
    exit 1
  fi
  if ! write_release_completion_proof; then
    exit 1
  fi
  release_is_complete=1
fi
rollback_tool_path="$release_root/tools/rollback-linux.py"
if [ ! -x "$rollback_tool_path" ]; then
  echo "Release-owned Linux rollback tool is missing or not executable: $rollback_tool_path" >&2
  exit 1
fi

docker load --input images/runtime-images.tar

if [ ! -f "$etc_root/platform-agent.json" ]; then
  platform_agent_configuration_created=1
  api_token=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
  cat >"$etc_root/platform-agent.json" <<EOF
{
  "schemaVersion": 1,
  "listenAddress": "127.0.0.1:18321",
  "apiToken": "$api_token",
  "runtimeExecutable": "/opt/vitalserver/current/bin/vitalserver-runtime-provider",
  "runtimeEndpointDocument": "/var/lib/vitalserver/run/runtime-endpoint.json",
  "runtimeProviderDocument": "/var/lib/vitalserver/run/runtime-provider.json",
  "operationLeaseDocument": "/var/lib/vitalserver/run/operation-lease.json",
  "installDocument": "/var/lib/vitalserver/install.json",
  "runtimeControllerPort": 18330,
  "pwaDirectory": "/opt/vitalserver/current/pwa",
  "delivery": {
    "workflowDocument": "/var/lib/vitalserver/run/platform-workflow.json",
    "updateTool": "/opt/vitalserver/current/tools/update-linux.py",
    "rollbackTool": "$rollback_tool_path",
    "uninstallTool": "/opt/vitalserver/current/tools/uninstall-linux.py",
    "supportExportTool": "/opt/vitalserver/current/tools/support-export-linux.py",
    "schedulerExecutable": "/usr/bin/systemd-run",
    "schedulerKind": "systemd-transient",
    "applyPolicy": "verify-only",
    "trustedBundleInbox": "/var/lib/vitalserver/inbox"
  },
  "platformServices": {
    "runtime-provider": "vitalserver-runtime-provider.service",
    "public-proxy": null,
    "log-sync": null,
    "sleep-prevention": null,
    "watchdog": null
  }
}
EOF
  chmod 0600 "$etc_root/platform-agent.json"
  printf '%s\n' "$api_token" >"$etc_root/secrets/platform-api-token"
  chmod 0600 "$etc_root/secrets/platform-api-token"
else
  if [ ! -s "$etc_root/secrets/platform-api-token" ]; then
    echo "Existing Platform Agent config has no explicit API token owner file; refusing to infer or replace configuration." >&2
    exit 1
  fi
  api_token=$(tr -d '\r\n' < "$etc_root/secrets/platform-api-token")
  install -m 0600 "$etc_root/platform-agent.json" "$platform_agent_configuration_backup"
  platform_agent_configuration_backed_up=1
  python3 - "$etc_root/platform-agent.json" "$api_token" "$rollback_tool_path" <<'PY'
import json
import os
import re
import sys
import tempfile

path, api_token, rollback_tool_path = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as stream:
        document = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"Platform Agent configuration migration input is invalid: {error}")

if document.get("schemaVersion") != 1:
    raise SystemExit("Platform Agent configuration migration requires schemaVersion=1")
if document.get("apiToken") != api_token:
    raise SystemExit("Platform Agent configuration token does not match its owner file")
delivery = document.get("delivery")
if not isinstance(delivery, dict):
    raise SystemExit("Platform Agent configuration migration requires delivery owner")

legacy_rollback_tool = "/opt/vitalserver/current/tools/rollback-linux.py"
existing_rollback_tool = delivery.get("rollbackTool")
if existing_rollback_tool is not None:
    if not isinstance(existing_rollback_tool, str) or not (
        existing_rollback_tool == legacy_rollback_tool
        or re.fullmatch(
            r"/opt/vitalserver/releases/[A-Za-z0-9._+-]+/tools/rollback-linux\.py",
            existing_rollback_tool,
        )
    ):
        raise SystemExit(
            "Platform Agent configuration migration rollbackTool is invalid: "
            f"{existing_rollback_tool!r}"
        )
    if not os.path.isfile(existing_rollback_tool) or not os.access(
        existing_rollback_tool, os.X_OK
    ):
        raise SystemExit(
            "Platform Agent configuration migration rollbackTool is unavailable: "
            f"{existing_rollback_tool}"
        )
if not re.fullmatch(
    r"/opt/vitalserver/releases/[A-Za-z0-9._+-]+/tools/rollback-linux\.py",
    rollback_tool_path,
):
    raise SystemExit(
        "Platform Agent configuration migration target rollbackTool is invalid: "
        f"{rollback_tool_path}"
    )

required = {
    "uninstallTool": "/opt/vitalserver/current/tools/uninstall-linux.py",
    "supportExportTool": "/opt/vitalserver/current/tools/support-export-linux.py",
    "schedulerKind": "systemd-transient",
    "trustedBundleInbox": "/var/lib/vitalserver/inbox",
}
for name, expected in required.items():
    existing = delivery.get(name)
    if existing not in (None, expected):
        raise SystemExit(
            f"Platform Agent configuration migration field mismatch: {name}={existing!r}"
        )
    delivery[name] = expected
delivery["rollbackTool"] = rollback_tool_path

directory = os.path.dirname(path)
descriptor, temporary = tempfile.mkstemp(
    dir=directory, prefix=".platform-agent.json.", suffix=".tmp"
)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(document, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY
fi

if [ ! -f "$etc_root/native-runtime-provider.json" ]; then
  native_provider_configuration_created=1
  docker_path=$(command -v docker)
  cat >"$etc_root/native-runtime-provider.json" <<EOF
{
  "schemaVersion": 1,
  "composeExecutable": "$docker_path",
  "composeFile": "/opt/vitalserver/current/runtime-bundle/compose.yaml",
  "composeEnvironmentFile": "/etc/vitalserver/runtime.env",
  "composeProjectName": "vitalserver",
  "projectDirectory": "/opt/vitalserver/current/runtime-bundle",
  "runtimeReadyURL": "http://127.0.0.1:18330/ready",
  "runtimeEndpointAddress": "127.0.0.1",
  "runtimeEndpointDocument": "/var/lib/vitalserver/run/runtime-endpoint.json",
  "runtimeProviderDocument": "/var/lib/vitalserver/run/runtime-provider.json",
  "readinessProbeTimeoutSeconds": 20,
  "startupTimeoutSeconds": 180,
  "shutdownTimeoutSeconds": 120
}
EOF
  chmod 0600 "$etc_root/native-runtime-provider.json"
fi

install -m 0644 packaging/vitalserver-platform-agent.service "$unit_root/vitalserver-platform-agent.service"
install -m 0644 packaging/vitalserver-runtime-controller.service "$unit_root/vitalserver-runtime-controller.service"
install -m 0644 packaging/vitalserver-runtime-provider.service "$unit_root/vitalserver-runtime-provider.service"
units_installed=1

if ! ln -s "releases/$version" "$current_link.next.$$" || \
  ! mv -Tf "$current_link.next.$$" "$current_link"; then
  echo "Linux current release publish failed: releases/$version" >&2
  exit 1
fi
if ! sync_directory "$opt_root"; then
  echo "Linux current release directory durability failed: $opt_root" >&2
  exit 1
fi

systemctl daemon-reload
systemctl enable vitalserver-platform-agent.service vitalserver-runtime-provider.service vitalserver-runtime-controller.service
services_enabled=1
systemctl restart vitalserver-runtime-provider.service
systemctl restart vitalserver-runtime-controller.service
systemctl restart vitalserver-platform-agent.service

attempt=0
while [ "$attempt" -lt 180 ]; do
  if curl --fail --silent --show-error \
    --header "Authorization: Bearer $api_token" \
    http://127.0.0.1:18321/platform >/dev/null 2>&1 && \
    curl --fail --silent --show-error \
      --header "Authorization: Bearer $api_token" \
      http://127.0.0.1:18321/runtime/capabilities >/dev/null 2>&1; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done
if [ "$attempt" -ge 180 ]; then
  echo "Installed Runtime acceptance timed out: Platform or Runtime API unavailable." >&2
  exit 1
fi

python3 packaging/acceptance-linux.py \
  --api-token-path "$etc_root/secrets/platform-api-token" \
  --runtime-provider-document "$var_root/run/runtime-provider.json" \
  --output-manifest "$var_root/proof/linux-native-acceptance.json" \
  --base-url http://127.0.0.1:18321 \
  --timeout-seconds 180 \
  --http-timeout-seconds 120 \
  --support-export-mode "$acceptance_support_export_mode"
acceptance_run_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["runId"])' \
  "$var_root/proof/linux-native-acceptance.json")

previous_release_for_owner=$install_transaction_previous_target
if [ "$previous_release_for_owner" = "releases/$version" ]; then
  previous_release_for_owner=$(read_installed_owner_previous_release)
  if [ "$previous_release_for_owner" = "-" ]; then
    previous_release_for_owner=""
  fi
fi

installed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
installed_boot_id=$(tr -d '\r\n' </proc/sys/kernel/random/boot_id)
install_document="$var_root/.install.json.$$"
cat >"$install_document" <<EOF
{
  "schemaVersion": 1,
  "state": "installed",
  "platformVersion": "$version",
  "runtimeBundleVersion": "$runtime_bundle_version",
  "installedAcceptanceRunId": "$acceptance_run_id",
  "installedAt": "$installed_at",
  "installedBootId": "$installed_boot_id",
  "previousRelease": $(if [ -n "$previous_release_for_owner" ]; then printf '"%s"' "$previous_release_for_owner"; else printf 'null'; fi)
}
EOF
chmod 0600 "$install_document"
sync "$install_document"
# This is the final commit boundary.  From here a rollback could restore B
# while leaving C's owner published, so preserve the matching transaction for
# retry instead.  The individual publish failures below report that state.
trap - EXIT HUP INT TERM
if ! mv -f "$install_document" "$var_root/install.json"; then
  echo "VitalServer Linux install failed version=$version rollbackState=preserved-for-retry phase=install-owner-publish reason=rename transaction=$install_transaction_document" >&2
  exit 1
fi
if ! sync_directory "$var_root"; then
  echo "VitalServer Linux install failed version=$version rollbackState=preserved-for-retry phase=install-owner-publish reason=directory-durability transaction=$install_transaction_document" >&2
  exit 1
fi

# The owner is now durable.  Transaction cleanup is only reconciliation, not
# a reason to undo the committed owner.

if ! rm -f "$install_transaction_document"; then
  echo "VitalServer Linux install failed version=$version rollbackState=preserved-for-retry phase=install-transaction-cleanup reason=remove transaction=$install_transaction_document" >&2
  exit 1
fi
if ! sync_directory "$etc_root"; then
  echo "VitalServer Linux install failed version=$version commitState=owner-published transactionState=cleanup-durability-unknown transaction=$install_transaction_document" >&2
  exit 1
fi
install_transaction_active=0

rm -f "$platform_agent_configuration_backup"
platform_agent_configuration_backed_up=0
rm -f "$runtime_environment_backup"
runtime_environment_backed_up=0
rm -f \
  "$platform_agent_unit_backup" \
  "$runtime_controller_unit_backup" \
  "$runtime_provider_unit_backup"
units_backed_up=0
echo "VitalServer Linux install passed platformVersion=$version runtimeBundleVersion=$runtime_bundle_version"
