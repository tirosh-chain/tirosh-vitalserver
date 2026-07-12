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

for command in sha256sum docker systemctl systemd-run install cp cmp mv ln od tr curl flock python3 sync cat; do
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
previous_target=""
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

if [ -L "$current_link" ]; then
  previous_target=$(readlink "$current_link")
fi

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

require_systemd_unit_directory() {
  directory=$1
  label=$2
  if [ ! -d "$directory" ] || [ -L "$directory" ]; then
    echo "$label is not a directory: $directory" >&2
    return 1
  fi
  for unit in \
    vitalserver-platform-agent.service \
    vitalserver-runtime-controller.service \
    vitalserver-runtime-provider.service; do
    if [ ! -f "$directory/$unit" ] || [ -L "$directory/$unit" ]; then
      echo "$label is incomplete: $directory/$unit" >&2
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
}

if [ -n "$previous_target" ] && ! validate_release_target "$previous_target"; then
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
  rollback_failed=0
  release_restored=1
  owner_configuration_restored=1
  units_restored=1
  if ! rm -rf \
    "$staging_root" \
    "$current_link.next.$$" \
    "$var_root/.install.json.$$" \
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
      ! mv -Tf "$current_link.rollback.$$" "$current_link"; then
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
  if [ "$release_systemd_snapshot_created" -eq 1 ] && \
    ! rm -rf "$release_systemd_snapshot_path"; then
    echo "Linux install rollback created systemd snapshot cleanup failed path=$release_systemd_snapshot_path" >&2
    rollback_failed=1
  fi
  if [ "$release_created" -eq 1 ]; then
    if ! rm -rf "$release_root"; then
      echo "Linux install rollback created release cleanup failed release=$release_root" >&2
      rollback_failed=1
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

install -d -m 0755 "$opt_root/releases" "$etc_root" "$unit_root"
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

if [ -e "$release_root" ]; then
  if [ ! -f "$release_root/release.json" ] || ! cmp -s release.json "$release_root/release.json"; then
    echo "Installed release version already exists with different identity: $release_root" >&2
    exit 1
  fi
  rm -rf "$staging_root"
else
  mv "$staging_root" "$release_root"
  release_created=1
  # A venv embeds absolute interpreter paths in its console scripts.  Build it
  # only after the immutable release tree has its final pathname; building it
  # under staging_root would leave the Runtime Controller with a broken shebang
  # as soon as this directory is published.
  VITALSERVER_RUNTIME_CONTROLLER_SETTINGS_PATH="$etc_root/runtime-controller.toml" \
    python3 "$release_root/runtime-controller/install-guest-tools-runtime.py" \
      --wheel-dir "$release_root/runtime-controller/python-wheels" \
      --guest-tools-home "$release_root/runtime-controller"
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

ln -s "releases/$version" "$current_link.next.$$"
mv -Tf "$current_link.next.$$" "$current_link"

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

previous_release_for_owner="$previous_target"
if [ "$previous_target" = "releases/$version" ]; then
  previous_release_for_owner=$(python3 - "$var_root/install.json" "$version" <<'PY'
import json
import re
import sys

path, version = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as stream:
        document = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"same-version install owner is unavailable or invalid: {error}")

if document.get("state") != "installed" or document.get("platformVersion") != version:
    raise SystemExit("same-version install owner identity does not match the current release")
previous_release = document.get("previousRelease")
if previous_release is None:
    print("")
elif not isinstance(previous_release, str) or not re.fullmatch(
    r"releases/[A-Za-z0-9._+-]+", previous_release
):
    raise SystemExit("same-version install owner has an invalid previousRelease")
elif previous_release == f"releases/{version}":
    raise SystemExit("same-version install owner previousRelease points to itself")
else:
    print(previous_release)
PY
  )
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
mv -f "$install_document" "$var_root/install.json"

rm -f "$platform_agent_configuration_backup"
platform_agent_configuration_backed_up=0
rm -f "$runtime_environment_backup"
runtime_environment_backed_up=0
rm -f \
  "$platform_agent_unit_backup" \
  "$runtime_controller_unit_backup" \
  "$runtime_provider_unit_backup"
units_backed_up=0
trap - EXIT HUP INT TERM
echo "VitalServer Linux install passed platformVersion=$version runtimeBundleVersion=$runtime_bundle_version"
