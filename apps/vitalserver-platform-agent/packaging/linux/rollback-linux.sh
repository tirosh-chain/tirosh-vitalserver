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
cp "$install_document" "$install_document_backup"
chmod 0600 "$install_document_backup"

restore_current() {
  status=$?
  trap - EXIT HUP INT TERM
  ln -s "$current_target" "$current_link.restore.$$"
  mv -Tf "$current_link.restore.$$" "$current_link"
  if [ -f "$install_document_backup" ]; then
    mv -f "$install_document_backup" "$install_document"
  fi
  systemctl daemon-reload || true
  systemctl restart vitalserver-runtime-provider.service || true
  systemctl restart vitalserver-runtime-controller.service || true
  systemctl restart vitalserver-platform-agent.service || true
  echo "VitalServer Linux rollback failed; original release restored target=$current_target" >&2
  exit "$status"
}
trap restore_current EXIT HUP INT TERM

ln -s "$previous_target" "$current_link.rollback.$$"
mv -Tf "$current_link.rollback.$$" "$current_link"
systemctl daemon-reload
systemctl restart vitalserver-runtime-provider.service
systemctl restart vitalserver-runtime-controller.service
systemctl restart vitalserver-platform-agent.service

python3 "$opt_root/$previous_target/tools/acceptance-linux.py" \
  --api-token-path "$token_path" \
  --runtime-provider-document "$var_root/run/runtime-provider.json" \
  --output-manifest "$var_root/proof/linux-native-rollback-acceptance.json" \
  --base-url http://127.0.0.1:18321 \
  --timeout-seconds 180

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
