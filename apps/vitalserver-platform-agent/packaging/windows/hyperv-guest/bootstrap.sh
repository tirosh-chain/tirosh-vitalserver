#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR=/opt/vitalserver/deploy
GUEST_TOOLS_HOME=/opt/tirosh/guest-tools
GUEST_TOOLS_VENV=${GUEST_TOOLS_HOME}/venv
SETTINGS_SOURCE=/opt/vitalserver/hyperv-guest/guest-tools.toml

if [ "$(id -u)" -ne 0 ]; then
  printf 'Hyper-V guest bootstrap requires root.\n' >&2
  exit 1
fi

runtime_device=$(findfs LABEL=vital-runtime)
if [ -z "${runtime_device}" ]; then
  printf 'Hyper-V guest Runtime data disk is unavailable: label=vital-runtime\n' >&2
  exit 1
fi

install -d -m 0755 /mnt/runtime /mnt/tirosh /mnt/tirosh-vital-files
if ! mountpoint -q /mnt/runtime; then
  mount "${runtime_device}" /mnt/runtime
fi
install -d -m 0755 /mnt/runtime/run /mnt/runtime/vital-files /opt/vitalserver/run
install -d -m 0700 /mnt/runtime/config
for config_name in runtime-config.json runtime-settings.json runtime.env; do
  config_source="${DEPLOY_DIR}/${config_name}"
  config_target="/mnt/runtime/config/${config_name}"
  if [ ! -f "${config_target}" ]; then
    if [ ! -s "${config_source}" ]; then
      printf 'Hyper-V guest initial Runtime configuration is missing: %s\n' "${config_source}" >&2
      exit 1
    fi
    if [ "${config_name}" = runtime.env ]; then
      runtime_env_temporary="${config_target}.installing.$$"
      install -m 0600 "${config_source}" "${runtime_env_temporary}"
      printf '%s\n' \
        'VITALSERVER_REDIS_RELAY_CONFIG_DIR=/mnt/runtime/config/redis-relay' \
        'VITALSERVER_REDIS_RELAY_SECRETS_DIR=/mnt/runtime/config/redis-relay-secrets' \
        'VITALSERVER_REDIS_RELAY_STATUS_DIR=/mnt/runtime/run/redis-relay-status' \
        >>"${runtime_env_temporary}"
      mv -f "${runtime_env_temporary}" "${config_target}"
    else
      install -m 0600 "${config_source}" "${config_target}"
    fi
  elif [ ! -s "${config_target}" ]; then
    printf 'Hyper-V guest persistent Runtime configuration is empty: %s\n' "${config_target}" >&2
    exit 1
  fi
done
install -d -m 0750 /mnt/runtime/config/redis-relay
install -d -m 0700 /mnt/runtime/config/redis-relay-secrets
relay_config=/mnt/runtime/config/redis-relay/redis-relay.toml
if [ ! -f "${relay_config}" ]; then
  relay_config_source=${DEPLOY_DIR}/redis-relay-config/redis-relay.toml
  if [ ! -s "${relay_config_source}" ]; then
    printf 'Hyper-V guest initial Redis Relay configuration is missing: %s\n' "${relay_config_source}" >&2
    exit 1
  fi
  install -m 0600 "${relay_config_source}" "${relay_config}"
elif [ ! -s "${relay_config}" ]; then
  printf 'Hyper-V guest persistent Redis Relay configuration is empty: %s\n' "${relay_config}" >&2
  exit 1
fi
if ! mountpoint -q /mnt/tirosh; then
  mount --bind /opt/vitalserver /mnt/tirosh
fi
if ! mountpoint -q /mnt/tirosh/run; then
  mount --bind /mnt/runtime/run /mnt/tirosh/run
fi
if ! mountpoint -q /mnt/tirosh-vital-files; then
  mount --bind /mnt/runtime/vital-files /mnt/tirosh-vital-files
fi

install -d -m 0755 /etc/tirosh
install -m 0644 "${SETTINGS_SOURCE}" /etc/tirosh/guest-tools.toml
python3 "${DEPLOY_DIR}/install-guest-tools-runtime.py" \
  --wheel-dir "${DEPLOY_DIR}/python-wheels" \
  --guest-tools-home "${GUEST_TOOLS_HOME}"
exec "${GUEST_TOOLS_VENV}/bin/tirosh-vitalserver-bootstrap"
