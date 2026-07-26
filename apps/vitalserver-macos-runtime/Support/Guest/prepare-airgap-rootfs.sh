#!/usr/bin/env bash
set -Euo pipefail

MOUNT_TAG="tirosh"
MOUNT_POINT="/mnt/tirosh"
DEPLOY_DIR="${MOUNT_POINT}/deploy"
VITAL_FILES_MOUNT_TAG="tirosh-vital-files"
VITAL_FILES_MOUNT_POINT="/mnt/tirosh-vital-files"
RUNTIME_DIR="${MOUNT_POINT}/run"
READY_FILE="${RUNTIME_DIR}/rootfs-ready"
RUNTIME_MANIFEST_FILE="${RUNTIME_DIR}/rootfs-runtime-manifest.json"
FAILURE_FILE="${RUNTIME_DIR}/rootfs-failure.json"
IDENTITY_CLEANUP_FILE="${RUNTIME_DIR}/rootfs-identity-cleanup.json"
APT_PLAN_TEXT_FILE="${RUNTIME_DIR}/rootfs-apt-plan.txt"
APT_PLAN_JSON_FILE="${RUNTIME_DIR}/rootfs-apt-plan.json"
APT_PROGRESS_JSON_FILE="${RUNTIME_DIR}/rootfs-apt-progress.json"
APT_INSTALLED_TEXT_FILE="${RUNTIME_DIR}/rootfs-apt-installed.txt"
APT_INSTALLED_JSON_FILE="${RUNTIME_DIR}/rootfs-apt-installed.json"
APT_BASE_PROOF_FILE="/var/lib/vitalserver/rootfs-apt-base.json"
APT_PACKAGES_FILE="${DEPLOY_DIR}/rootfs-apt-packages.txt"
APT_SNAPSHOT_CONF="/etc/apt/apt.conf.d/50vitalserver-snapshot"
POLICY_RC_D="/usr/sbin/policy-rc.d"
POLICY_RC_D_BACKUP="/usr/sbin/policy-rc.d.vitalserver-backup"
GUEST_TOOLS_HOME="/opt/tirosh/guest-tools"
GUEST_TOOLS_VENV="${GUEST_TOOLS_HOME}/venv"
GUEST_TOOLS_INSTALL_PROOF_FILE="${GUEST_TOOLS_HOME}/install-proof.json"
PYTHON_WHEEL_DIR="${DEPLOY_DIR}/python-wheels"
ROOTFS_STAGE="startup"
ROOTFS_FAILURE_RECORDED=0
APT_INDEX_UPDATE_TIMEOUT_SECONDS=1800
APT_INSTALL_TIMEOUT_SECONDS=1800
APT_PROGRESS_INTERVAL_SECONDS=30

RUNTIME_APT_PACKAGES=()

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

record_failure_once() {
  local exit_code="$1"
  local stage="$2"

  if [ "${ROOTFS_FAILURE_RECORDED}" -eq 1 ]; then
    return
  fi
  ROOTFS_FAILURE_RECORDED=1

  if [ ! -d "${RUNTIME_DIR}" ]; then
    return
  fi

  python3 - "${FAILURE_FILE}" "${MOUNT_POINT}/deploy/build-metadata/rootfs-input.json" "${stage}" "${exit_code}" "${APT_PROGRESS_JSON_FILE}" "${APT_PLAN_JSON_FILE}" "${RUNTIME_MANIFEST_FILE}" <<'PY' || true
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

failure_path = Path(sys.argv[1])
input_path = Path(sys.argv[2])
stage = sys.argv[3]
exit_code = int(sys.argv[4])
apt_progress_path = Path(sys.argv[5])
apt_plan_path = Path(sys.argv[6])
manifest_path = Path(sys.argv[7])
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
            "aptProgressPath": str(apt_progress_path),
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

# ERR is the explicit fail-fast boundary. Bash does not invoke it for every
# expansion failure, so EXIT writes the same failure proof for those paths and
# returns Bash's original status (for example, 127 for nounset).
handle_rootfs_error() {
  local exit_code="$1"

  trap - ERR
  set +e
  record_failure_once "${exit_code}" "${ROOTFS_STAGE}"
  exit "${exit_code}"
}

handle_rootfs_exit() {
  local exit_code="$1"

  trap - ERR EXIT
  set +e
  if [ "${exit_code}" -ne 0 ]; then
    record_failure_once "${exit_code}" "${ROOTFS_STAGE}"
  fi
  exit "${exit_code}"
}

trap 'handle_rootfs_error "$?"' ERR
trap 'handle_rootfs_exit "$?"' EXIT

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

read_runtime_apt_packages() {
  ROOTFS_STAGE="apt-package-contract"
  if [ ! -s "${APT_PACKAGES_FILE}" ]; then
    printf "error: rootfs APT package contract is unavailable: %s\n" "${APT_PACKAGES_FILE}" >&2
    return 1
  fi
  mapfile -t RUNTIME_APT_PACKAGES < <(
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "${APT_PACKAGES_FILE}"
  )
  if [ "${#RUNTIME_APT_PACKAGES[@]}" -eq 0 ]; then
    printf "error: rootfs APT package contract is empty: %s\n" "${APT_PACKAGES_FILE}" >&2
    return 1
  fi
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

record_apt_progress() {
  local stage="$1"
  local status="$2"
  local active_command="$3"
  local command_timeout_seconds="$4"

  python3 - "${APT_PROGRESS_JSON_FILE}" "${MOUNT_POINT}/deploy/build-metadata/rootfs-input.json" "${stage}" "${status}" "${active_command}" "${command_timeout_seconds}" <<'PY'
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

output = Path(sys.argv[1])
metadata_path = Path(sys.argv[2])
stage = sys.argv[3]
status = sys.argv[4]
active_command = sys.argv[5]
command_timeout_seconds = int(sys.argv[6])
metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
run_id = metadata.get("runId")
if not isinstance(run_id, str) or not run_id:
    raise SystemExit("error: rootfs input metadata is missing runId")
document = {
    "schemaVersion": 1,
    "runId": run_id,
    "stage": stage,
    "status": status,
    "updatedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "activeCommand": active_command,
    "activeCommandTimeoutSeconds": command_timeout_seconds,
}
temporary = output.with_suffix(output.suffix + ".tmp")
temporary.write_text(
    json.dumps(document, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
temporary.replace(output)
PY
}

run_apt_command_with_progress() {
  local stage="$1"
  local command_timeout_seconds="$2"
  local active_command="$3"
  local command_pid
  local command_status
  shift 3

  ROOTFS_STAGE="${stage}"
  record_apt_progress \
    "${ROOTFS_STAGE}" \
    "running" \
    "${active_command}" \
    "${command_timeout_seconds}"
  timeout --signal=TERM "${command_timeout_seconds}" "$@" &
  command_pid="$!"
  while kill -0 "${command_pid}" >/dev/null 2>&1; do
    sleep "${APT_PROGRESS_INTERVAL_SECONDS}"
    if kill -0 "${command_pid}" >/dev/null 2>&1; then
      record_apt_progress \
        "${ROOTFS_STAGE}" \
        "running" \
        "${active_command}" \
        "${command_timeout_seconds}"
    fi
  done
  command_status=0
  wait "${command_pid}" || command_status="$?"
  if [ "${command_status}" -ne 0 ]; then
    record_apt_progress \
      "${ROOTFS_STAGE}" \
      "failed" \
      "${active_command}" \
      "${command_timeout_seconds}"
    return "${command_status}"
  fi
  record_apt_progress \
    "${ROOTFS_STAGE}" \
    "passed" \
    "${active_command}" \
    "${command_timeout_seconds}"
}

update_apt_indexes() {
  run_apt_command_with_progress \
    "apt-index-update" \
    "${APT_INDEX_UPDATE_TIMEOUT_SECONDS}" \
    "apt-get update" \
    apt-get \
    -o Acquire::Retries=5 \
    -o APT::Update::Error-Mode=any \
    update
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

write_apt_base_proof() {
  ROOTFS_STAGE="apt-base-proof"
  mkdir -p "$(dirname "${APT_BASE_PROOF_FILE}")"
  python3 - "${APT_BASE_PROOF_FILE}" "${APT_INSTALLED_JSON_FILE}" "${APT_SNAPSHOT}" "${RUNTIME_APT_PACKAGES[*]}" <<'PY'
import json
import sys
from datetime import UTC, datetime
from pathlib import Path

output = Path(sys.argv[1])
installed_path = Path(sys.argv[2])
snapshot = sys.argv[3]
required_packages = sorted(value for value in sys.argv[4].split() if value)
installed = json.loads(installed_path.read_text(encoding="utf-8"))
packages = installed.get("packages")
if not isinstance(packages, dict):
    raise SystemExit("error: installed APT package proof has no packages object")
missing = sorted(package for package in required_packages if package not in packages)
if missing:
    raise SystemExit(
        "error: cannot publish APT base proof; missing packages: " + ",".join(missing)
    )
document = {
    "schemaVersion": 1,
    "status": "passed",
    "snapshot": snapshot,
    "requiredPackages": required_packages,
    "installedPackages": packages,
    "preparedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
temporary = output.with_suffix(output.suffix + ".tmp")
temporary.write_text(
    json.dumps(document, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
temporary.replace(output)
PY
}

verify_apt_base_proof() {
  ROOTFS_STAGE="apt-base-verify"
  APT_SNAPSHOT="$(read_apt_snapshot)"
  export APT_SNAPSHOT
  python3 - "${APT_BASE_PROOF_FILE}" "${APT_INSTALLED_JSON_FILE}" "${APT_PLAN_JSON_FILE}" "${MOUNT_POINT}/deploy/build-metadata/rootfs-input.json" "${APT_SNAPSHOT}" "${RUNTIME_APT_PACKAGES[*]}" "${ROOTFS_BLOCKED_UPGRADE_PACKAGES[*]}" <<'PY'
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

proof_path = Path(sys.argv[1])
installed_output = Path(sys.argv[2])
plan_output = Path(sys.argv[3])
metadata_path = Path(sys.argv[4])
expected_snapshot = sys.argv[5]
required_packages = sorted(value for value in sys.argv[6].split() if value)
guard_packages = sorted(value for value in sys.argv[7].split() if value)
try:
    proof = json.loads(proof_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"error: APT base proof is unavailable or invalid: {proof_path}: {error}")
if (
    not isinstance(proof, dict)
    or proof.get("schemaVersion") != 1
    or proof.get("status") != "passed"
    or proof.get("snapshot") != expected_snapshot
    or proof.get("requiredPackages") != required_packages
):
    raise SystemExit(
        "error: APT base proof contract mismatch: "
        f"path={proof_path} expectedSnapshot={expected_snapshot}"
    )
proof_packages = proof.get("installedPackages")
if not isinstance(proof_packages, dict):
    raise SystemExit(f"error: APT base proof has no installedPackages object: {proof_path}")
actual_packages = {}
for package in required_packages + ["containerd", "runc"]:
    completed = subprocess.run(
        ["dpkg-query", "-W", "-f=${Version}", package],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise SystemExit(f"error: cached APT base is missing package: {package}")
    actual_packages[package] = completed.stdout.strip()
    if proof_packages.get(package) != actual_packages[package]:
        raise SystemExit(
            "error: cached APT base package version differs from proof: "
            f"package={package} proof={proof_packages.get(package)!r} "
            f"actual={actual_packages[package]!r}"
        )
audit = subprocess.run(["dpkg", "--audit"], capture_output=True, text=True, check=False)
if audit.returncode != 0 or audit.stdout.strip() or audit.stderr.strip():
    raise SystemExit(
        "error: cached APT base has incomplete dpkg state: "
        + (audit.stdout or audit.stderr).strip()
    )
installed_output.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "generatedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "source": "verified-apt-base-cache",
            "packages": actual_packages,
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
run_id = metadata.get("runId")
if not isinstance(run_id, str) or not run_id:
    raise SystemExit("error: rootfs input metadata is missing runId")
plan_output.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "runId": run_id,
            "generatedAt": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "status": "allowed",
            "source": "verified-apt-base-cache",
            "snapshot": expected_snapshot,
            "installPackages": required_packages,
            "guardPackages": guard_packages,
            "blockedUpgrades": [],
            "newPackages": [],
            "upgradedPackages": [],
            "removedPackages": [],
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY
  record_apt_progress \
    "apt-base-verify" \
    "passed" \
    "verify cached APT base proof" \
    "0"
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

  update_apt_indexes
  record_apt_plan
  ROOTFS_STAGE="apt-install"
  install_service_start_blocker
  apt_install_status=0
  run_apt_command_with_progress \
    "apt-install" \
    "${APT_INSTALL_TIMEOUT_SECONDS}" \
    "apt-get install" \
    apt-get install -y --no-install-recommends "${RUNTIME_APT_PACKAGES[@]}" \
    || apt_install_status="$?"
  remove_service_start_blocker
  if [ "${apt_install_status}" -ne 0 ]; then
    return "${apt_install_status}"
  fi
  record_installed_runtime_packages
  write_apt_base_proof

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
  ROOTFS_STAGE="guest-tools-install"
  python3 "${DEPLOY_DIR}/install-guest-tools-runtime.py" \
    --wheel-dir "${PYTHON_WHEEL_DIR}" \
    --guest-tools-home "${GUEST_TOOLS_HOME}"
  ln -sf "${GUEST_TOOLS_VENV}/bin/tirosh-vitalserver-rootfs-smoke" /usr/local/bin/tirosh-vitalserver-rootfs-smoke
}

mount_share "${MOUNT_TAG}" "${MOUNT_POINT}"
mount_share "${VITAL_FILES_MOUNT_TAG}" "${VITAL_FILES_MOUNT_POINT}"
mkdir -p "${RUNTIME_DIR}"

read_runtime_apt_packages
if [ -s "${APT_BASE_PROOF_FILE}" ]; then
  configure_guest_clock
  verify_apt_base_proof
  printf "Reusing verified APT-prepared rootfs base: %s\n" "${APT_BASE_PROOF_FILE}"
else
  install_runtime_packages
fi
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
python3 - "${RUNTIME_MANIFEST_FILE}" "${READY_FILE}" "${IDENTITY_CLEANUP_FILE}" "${GUEST_TOOLS_INSTALL_PROOF_FILE}" <<'PY'
import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

manifest_path = Path(sys.argv[1])
ready_path = Path(sys.argv[2])
identity_cleanup_path = Path(sys.argv[3])
guest_tools_install_proof_path = Path(sys.argv[4])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
identity_cleanup = json.loads(identity_cleanup_path.read_text(encoding="utf-8"))
try:
    guest_tools_install_proof = json.loads(
        guest_tools_install_proof_path.read_text(encoding="utf-8")
    )
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(
        "Guest Tools install proof is unavailable or invalid: "
        f"{guest_tools_install_proof_path}: {error}"
    ) from error
if not isinstance(guest_tools_install_proof, dict):
    raise SystemExit(
        "Guest Tools install proof must be an object: "
        f"{guest_tools_install_proof_path}"
    )
dependencies = guest_tools_install_proof.get("dependencies")
if (
    guest_tools_install_proof.get("status") != "passed"
    or not isinstance(guest_tools_install_proof.get("target"), str)
    or not isinstance(dependencies, dict)
    or not isinstance(dependencies.get("alembic"), str)
    or not isinstance(dependencies.get("sqlalchemy"), str)
):
    raise SystemExit(
        "Guest Tools install proof is incomplete: "
        f"{guest_tools_install_proof_path}"
    )


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
            "pythonDependencies": {
                "status": "passed",
                "proof": str(guest_tools_install_proof_path),
                "target": guest_tools_install_proof["target"],
                "dependencies": dependencies,
                "guestWheelSHA256": guest_tools_install_proof.get("guestWheelSHA256"),
                "requirementsSHA256": guest_tools_install_proof.get(
                    "requirementsSHA256"
                ),
            },
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY

printf "Air-gapped rootfs package prerequisites are ready.\n"
