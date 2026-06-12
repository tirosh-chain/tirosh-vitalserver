#!/usr/bin/env bash
set -eEuo pipefail

MOUNT_TAG="tirosh"
MOUNT_POINT="/mnt/tirosh"
VITAL_FILES_MOUNT_TAG="tirosh-vital-files"
VITAL_FILES_MOUNT_POINT="/mnt/tirosh-vital-files"
RUNTIME_DIR="${MOUNT_POINT}/run"
READY_FILE="${RUNTIME_DIR}/rootfs-ready"
RUNTIME_MANIFEST_FILE="${RUNTIME_DIR}/rootfs-runtime-manifest.json"
FAILURE_FILE="${RUNTIME_DIR}/rootfs-failure.json"
IDENTITY_CLEANUP_FILE="${RUNTIME_DIR}/rootfs-identity-cleanup.json"
APT_PLAN_TEXT_FILE="${RUNTIME_DIR}/rootfs-apt-plan.txt"
APT_PLAN_JSON_FILE="${RUNTIME_DIR}/rootfs-apt-plan.json"
APT_INSTALLED_TEXT_FILE="${RUNTIME_DIR}/rootfs-apt-installed.txt"
APT_INSTALLED_JSON_FILE="${RUNTIME_DIR}/rootfs-apt-installed.json"
APT_SNAPSHOT_CONF="/etc/apt/apt.conf.d/50vitalserver-snapshot"
POLICY_RC_D="/usr/sbin/policy-rc.d"
POLICY_RC_D_BACKUP="/usr/sbin/policy-rc.d.vitalserver-backup"
GUEST_TOOLS_HOME="/opt/tirosh/guest-tools"
GUEST_TOOLS_VENV="${GUEST_TOOLS_HOME}/venv"
PYTHON_WHEEL_DIR="${MOUNT_POINT}/deploy/python-wheels"
ROOTFS_STAGE="startup"

RUNTIME_APT_PACKAGES=(
  avahi-daemon
  busybox-static
  ca-certificates
  cloud-guest-utils
  curl
  docker.io
  docker-compose-v2
  procps
  psmisc
  python3-minimal
  python3-venv
  util-linux
)

ROOTFS_BLOCKED_UPGRADE_PACKAGES=(
  bsdextrautils
  bsdutils
  containerd
  curl
  docker.io
  eject
  fdisk
  libblkid1
  libcurl3t64-gnutls
  libcurl4t64
  libfdisk1
  libmount1
  libpython3-stdlib
  libpython3.12-minimal
  libpython3.12-stdlib
  libpython3.12t64
  libsmartcols1
  libuuid1
  mount
  python3
  python3-minimal
  python3-pkg-resources
  python3-setuptools
  python3.12
  python3.12-minimal
  runc
  util-linux
  uuid-runtime
)

if [ "$(id -u)" -ne 0 ]; then
  printf "error: run with sudo\n" >&2
  exit 1
fi

record_failure() {
  local exit_code="$1"
  local stage="$2"

  if [ "${exit_code}" -eq 0 ]; then
    return
  fi
  if [ ! -d "${RUNTIME_DIR}" ]; then
    return
  fi

  python3 - "${FAILURE_FILE}" "${MOUNT_POINT}/deploy/build-metadata/rootfs-input.json" "${stage}" "${exit_code}" "${APT_PLAN_JSON_FILE}" "${RUNTIME_MANIFEST_FILE}" <<'PY' || true
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

failure_path = Path(sys.argv[1])
input_path = Path(sys.argv[2])
stage = sys.argv[3]
exit_code = int(sys.argv[4])
apt_plan_path = Path(sys.argv[5])
manifest_path = Path(sys.argv[6])
run_id = ""
try:
    document = json.loads(input_path.read_text(encoding="utf-8"))
    if isinstance(document, dict) and isinstance(document.get("runId"), str):
        run_id = document["runId"]
except (OSError, json.JSONDecodeError):
    pass
failure_path.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "runId": run_id,
            "failedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "stage": stage,
            "exitCode": exit_code,
            "reason": "guest-rootfs-prepare-failed",
            "aptPlanPath": str(apt_plan_path),
            "manifestPath": str(manifest_path),
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY
}

trap 'record_failure "$?" "${ROOTFS_STAGE}"' ERR

mount_share() {
  local tag="$1"
  local mount_point="$2"

  mkdir -p "${mount_point}"
  if ! mountpoint -q "${mount_point}"; then
    mount -t virtiofs "${tag}" "${mount_point}"
  fi
}

disable_flash_kernel_hook() {
  local hook="/etc/initramfs/post-update.d/flash-kernel"
  if [ -x "${hook}" ]; then
    chmod -x "${hook}"
  fi
}

remove_flash_kernel_package() {
  if dpkg-query -W flash-kernel >/dev/null 2>&1; then
    apt-get purge -y flash-kernel \
      || dpkg --purge --force-all flash-kernel \
      || true
  fi
}

stop_background_apt_services() {
  systemctl stop \
    apt-daily.service \
    apt-daily.timer \
    apt-daily-upgrade.service \
    apt-daily-upgrade.timer \
    dpkg-db-backup.service \
    dpkg-db-backup.timer \
    packagekit.service \
    unattended-upgrades.service \
    >/dev/null 2>&1 || true
}

install_service_start_blocker() {
  if [ -e "${POLICY_RC_D}" ] && [ ! -e "${POLICY_RC_D_BACKUP}" ]; then
    mv "${POLICY_RC_D}" "${POLICY_RC_D_BACKUP}"
  fi
  cat >"${POLICY_RC_D}" <<'EOF'
#!/bin/sh
exit 101
EOF
  chmod 0755 "${POLICY_RC_D}"
}

remove_service_start_blocker() {
  if [ -e "${POLICY_RC_D_BACKUP}" ]; then
    mv "${POLICY_RC_D_BACKUP}" "${POLICY_RC_D}"
  elif [ -e "${POLICY_RC_D}" ]; then
    rm -f "${POLICY_RC_D}"
  fi
}

repair_package_state() {
  if ! dpkg --configure -a; then
    apt-get -f install -y
  fi
}

read_apt_snapshot() {
  python3 - "${MOUNT_POINT}/deploy/build-metadata/rootfs-input.json" <<'PY'
import json
import re
import sys
from pathlib import Path

metadata = Path(sys.argv[1])
document = json.loads(metadata.read_text(encoding="utf-8"))
ubuntu = document.get("ubuntu")
if not isinstance(ubuntu, dict):
    raise SystemExit("error: rootfs input metadata is missing ubuntu object")
snapshot = ubuntu.get("aptSnapshot")
if not isinstance(snapshot, str) or not re.fullmatch(r"\d{8}T\d{6}Z", snapshot):
    raise SystemExit(
        "error: rootfs input metadata has invalid ubuntu.aptSnapshot; "
        "expected YYYYMMDDTHHMMSSZ"
    )
print(snapshot)
PY
}

read_guest_clock_utc() {
  python3 - "${MOUNT_POINT}/deploy/build-metadata/rootfs-input.json" <<'PY'
import json
import re
import sys
from datetime import UTC, datetime
from pathlib import Path

metadata = Path(sys.argv[1])
document = json.loads(metadata.read_text(encoding="utf-8"))
guest_clock = document.get("guestClockUtc")
if not isinstance(guest_clock, str) or not re.fullmatch(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
    guest_clock,
):
    raise SystemExit(
        "error: rootfs input metadata has invalid guestClockUtc; "
        "expected YYYY-MM-DDTHH:MM:SSZ"
    )
datetime.strptime(guest_clock, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)
print(guest_clock)
PY
}

configure_guest_clock() {
  local guest_clock_utc

  ROOTFS_STAGE="guest-clock"
  guest_clock_utc="$(read_guest_clock_utc)"
  timedatectl set-ntp false >/dev/null 2>&1 || true
  date -u --set="${guest_clock_utc}" >/dev/null
  printf "Rootfs guest clock set to %s\n" "${guest_clock_utc}"
}

configure_apt_snapshot() {
  ROOTFS_STAGE="apt-snapshot"
  APT_SNAPSHOT="$(read_apt_snapshot)"
  export APT_SNAPSHOT
  rm -f "${APT_SNAPSHOT_CONF}"
  configure_snapshot_sources "${APT_SNAPSHOT}"
  clear_apt_indexes
}

configure_snapshot_sources() {
  local snapshot="$1"
  local source

  ROOTFS_STAGE="apt-snapshot-sources"
  for source in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if [ -e "${source}" ]; then
      mv "${source}" "${source}.vitalserver-disabled"
    fi
  done

  cat >"/etc/apt/sources.list.d/vitalserver-snapshot.sources" <<EOF
Types: deb
URIs: https://snapshot.ubuntu.com/ubuntu/${snapshot}
Suites: noble noble-updates noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
}

clear_apt_indexes() {
  ROOTFS_STAGE="apt-index-clean"
  rm -rf /var/lib/apt/lists/*
  mkdir -p /var/lib/apt/lists/partial
}

record_apt_plan() {
  ROOTFS_STAGE="apt-plan"
  apt-get -s install -y --no-install-recommends "${RUNTIME_APT_PACKAGES[@]}" >"${APT_PLAN_TEXT_FILE}"
  python3 - "${APT_PLAN_TEXT_FILE}" "${APT_PLAN_JSON_FILE}" "${ROOTFS_BLOCKED_UPGRADE_PACKAGES[*]}" "${RUNTIME_APT_PACKAGES[*]}" "${APT_SNAPSHOT}" "${MOUNT_POINT}/deploy/build-metadata/rootfs-input.json" <<'PY'
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

text_path = Path(sys.argv[1])
json_path = Path(sys.argv[2])
guard_packages = sorted(value for value in sys.argv[3].split() if value)
install_packages = sorted(value for value in sys.argv[4].split() if value)
apt_snapshot = sys.argv[5]
metadata_path = Path(sys.argv[6])
run_id = ""
try:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if isinstance(metadata, dict) and isinstance(metadata.get("runId"), str):
        run_id = metadata["runId"]
except (OSError, json.JSONDecodeError):
    run_id = ""
sections = {
    "The following NEW packages will be installed:": "newPackages",
    "The following packages will be upgraded:": "upgradedPackages",
    "The following packages will be REMOVED:": "removedPackages",
}
result = {value: [] for value in sections.values()}
current = None
for raw_line in text_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.rstrip()
    stripped = line.strip()
    if stripped in sections:
        current = sections[stripped]
        continue
    if current is None:
        continue
    if not line.startswith(" ") and not line.startswith("\t"):
        current = None
        continue
    result[current].extend(value for value in stripped.split() if value)
for key, values in result.items():
    result[key] = sorted(set(values))
blocked = sorted(set(result["upgradedPackages"]).intersection(guard_packages))
document = {
    "schemaVersion": 1,
    "runId": run_id,
    "generatedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": "blocked" if blocked else "allowed",
    "snapshot": apt_snapshot,
    "installPackages": install_packages,
    "guardPackages": guard_packages,
    "blockedUpgrades": blocked,
    **result,
}
json_path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if blocked:
    print(
        "error: rootfs apt plan mutates base runtime packages: "
        + ",".join(blocked),
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

record_installed_runtime_packages() {
  ROOTFS_STAGE="apt-installed"
  : >"${APT_INSTALLED_TEXT_FILE}"
  for package in "${RUNTIME_APT_PACKAGES[@]}" containerd runc; do
    version="$(dpkg-query -W -f='${Version}' "${package}" 2>/dev/null || true)"
    if [ -n "${version}" ]; then
      printf "%s\t%s\n" "${package}" "${version}" >>"${APT_INSTALLED_TEXT_FILE}"
    fi
  done
  python3 - "${APT_INSTALLED_JSON_FILE}" "${APT_INSTALLED_TEXT_FILE}" <<'PY'
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

output = Path(sys.argv[1])
installed = Path(sys.argv[2])
packages = {}
for line in installed.read_text(encoding="utf-8").splitlines():
    package, _, version = line.rstrip("\n").partition("\t")
    if package and version:
        packages[package] = version
output.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "generatedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "packages": packages,
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY
}

install_runtime_packages() {
  local apt_install_status

  export DEBIAN_FRONTEND=noninteractive

  ROOTFS_STAGE="apt-prepare"
  configure_guest_clock
  stop_background_apt_services
  configure_apt_snapshot
  disable_flash_kernel_hook
  remove_flash_kernel_package
  repair_package_state

  ROOTFS_STAGE="apt-update"
  apt-get update
  record_apt_plan
  ROOTFS_STAGE="apt-install"
  install_service_start_blocker
  apt_install_status=0
  apt-get install -y --no-install-recommends "${RUNTIME_APT_PACKAGES[@]}" || apt_install_status="$?"
  remove_service_start_blocker
  if [ "${apt_install_status}" -ne 0 ]; then
    return "${apt_install_status}"
  fi
  record_installed_runtime_packages

  apt-get clean
  rm -rf /var/lib/apt/lists/*
}

verify_python_venv() {
  local test_venv

  test_venv="$(mktemp -d)"
  if ! python3 -m venv "${test_venv}" >/dev/null 2>&1; then
    rm -rf "${test_venv}"
    printf "error: python3 venv cannot be created; ensure python3-venv and ensurepip are installed\n" >&2
    return 1
  fi
  if ! "${test_venv}/bin/python" -m pip --version >/dev/null 2>&1; then
    rm -rf "${test_venv}"
    printf "error: python3 venv was created without pip; ensure ensurepip is available\n" >&2
    return 1
  fi
  rm -rf "${test_venv}"
}

verify_runtime_packages() {
  verify_python_venv
  docker compose version >/dev/null
}

stop_rootfs_runtime_services() {
  ROOTFS_STAGE="rootfs-runtime-service-cleanup"
  systemctl stop docker.service docker.socket containerd.service >/dev/null 2>&1 || true
  rm -rf /run/docker /run/containerd /var/run/docker.sock /var/lib/docker/tmp/*
}

cleanup_rootfs_identity_state() {
  ROOTFS_STAGE="rootfs-identity-cleanup"
  rm -f /etc/ssh/ssh_host_* || true
  rm -rf /var/lib/cloud/instances /var/lib/cloud/instance /var/lib/cloud/data || true
  rm -rf /var/log/journal/* /run/log/journal/* || true
  journalctl --rotate >/dev/null 2>&1 || true
  journalctl --vacuum-time=1s >/dev/null 2>&1 || true
  truncate -s 0 /etc/machine-id
  rm -f /var/lib/dbus/machine-id || true
  python3 - "${IDENTITY_CLEANUP_FILE}" <<'PY'
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

path = Path(sys.argv[1])
proof = {
    "schemaVersion": 1,
    "status": "passed",
    "cleanedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "machineIdEmpty": Path("/etc/machine-id").read_text(encoding="utf-8") == "",
    "sshHostKeys": sorted(str(item) for item in Path("/etc/ssh").glob("ssh_host_*")),
    "cloudInitInstanceExists": Path("/var/lib/cloud/instance").exists()
        or Path("/var/lib/cloud/instances").exists(),
}
if not proof["machineIdEmpty"]:
    proof["status"] = "failed"
if proof["sshHostKeys"]:
    proof["status"] = "failed"
if proof["cloudInitInstanceExists"]:
    proof["status"] = "failed"
path.write_text(json.dumps(proof, indent=2, sort_keys=True) + "\n", encoding="utf-8")
if proof["status"] != "passed":
    raise SystemExit(1)
PY
}

install_guest_tools_for_rootfs_smoke() {
  local wheel

  ROOTFS_STAGE="guest-tools-install"
  wheel="$(find "${PYTHON_WHEEL_DIR}" -maxdepth 1 -name 'tirosh_vitalserver_guest_tools-*.whl' -type f | sort | tail -n 1 || true)"
  if [ -z "${wheel}" ]; then
    printf "error: missing guest tools wheel under %s\n" "${PYTHON_WHEEL_DIR}" >&2
    return 1
  fi

  mkdir -p "${GUEST_TOOLS_HOME}"
  python3 -m venv --clear "${GUEST_TOOLS_VENV}"
  "${GUEST_TOOLS_VENV}/bin/pip" install --no-index --no-deps "${wheel}"
  ln -sf "${GUEST_TOOLS_VENV}/bin/tirosh-vitalserver-rootfs-smoke" /usr/local/bin/tirosh-vitalserver-rootfs-smoke
}

mount_share "${MOUNT_TAG}" "${MOUNT_POINT}"
mount_share "${VITAL_FILES_MOUNT_TAG}" "${VITAL_FILES_MOUNT_POINT}"
mkdir -p "${RUNTIME_DIR}"

install_runtime_packages
ROOTFS_STAGE="runtime-package-verify"
verify_runtime_packages
install_guest_tools_for_rootfs_smoke
ROOTFS_STAGE="rootfs-smoke"
tirosh-vitalserver-rootfs-smoke
stop_rootfs_runtime_services
ROOTFS_STAGE="systemd-enable"
systemctl enable docker
systemctl enable avahi-daemon
cleanup_rootfs_identity_state

ROOTFS_STAGE="ready-marker"
python3 - "${RUNTIME_MANIFEST_FILE}" "${READY_FILE}" "${IDENTITY_CLEANUP_FILE}" <<'PY'
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

manifest_path = Path(sys.argv[1])
ready_path = Path(sys.argv[2])
identity_cleanup_path = Path(sys.argv[3])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
identity_cleanup = json.loads(identity_cleanup_path.read_text(encoding="utf-8"))


def command_output(command):
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    return (completed.stdout or completed.stderr).strip()


ready_path.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "runId": manifest["runId"],
            "readyAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "docker": command_output(["docker", "--version"]),
            "compose": command_output(["docker", "compose", "version"]),
            "identityCleanup": {
                "status": identity_cleanup.get("status"),
                "proof": str(identity_cleanup_path),
            },
            "manifest": str(manifest_path),
            "pythonVenv": "ready",
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY

printf "Air-gapped rootfs package prerequisites are ready.\n"
