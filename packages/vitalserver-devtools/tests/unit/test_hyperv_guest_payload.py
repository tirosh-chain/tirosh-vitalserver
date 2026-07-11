import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[4]
STAGER = ROOT / "scripts/stage_hyperv_guest_payload.py"


def test_hyperv_guest_payload_stages_native_owner_contract(tmp_path: Path) -> None:
    system_root = tmp_path / "system-root"
    system_root.mkdir()
    deploy = tmp_path / "deploy"
    deploy.mkdir()
    (deploy / "compose.yaml").write_text(
        "services:\n  controller:\n    environment:\n      URL: /runtime/capabilities\n",
        encoding="utf-8",
    )
    for config_name in ("runtime-config.json", "runtime-settings.json", "runtime.env"):
        (deploy / config_name).write_text("configured\n", encoding="utf-8")
    (deploy / "redis-relay-config").mkdir()
    (deploy / "redis-relay-config/redis-relay.toml").write_text(
        "[redis_relay]\nenabled = false\n", encoding="utf-8"
    )
    proof = tmp_path / "rootfs-proof.json"
    proof.write_text(
        json.dumps(
            {
                "runId": "run-1",
                "dockerImages": {
                    "platform": "linux/amd64",
                    "guestArchitecture": "x86_64",
                    "status": "passed",
                },
                "cleanup": {"status": "passed"},
            }
        ),
        encoding="utf-8",
    )
    output_proof = tmp_path / "hyperv-proof.json"

    subprocess.run(
        [
            sys.executable,
            str(STAGER),
            "--system-root",
            str(system_root),
            "--deploy-directory",
            str(deploy),
            "--rootfs-proof",
            str(proof),
            "--output-proof",
            str(output_proof),
        ],
        check=True,
    )

    target = system_root / "opt/vitalserver"
    assert (target / "deploy/compose.yaml").is_file()
    settings = (target / "hyperv-guest/guest-tools.toml").read_text(
        encoding="utf-8"
    )
    assert 'runtimeMountMode = "native"' in settings
    assert 'vitalFilesMountMode = "native"' in settings
    assert 'runtimeConfigFile = "/mnt/runtime/config/runtime-config.json"' in settings
    assert 'runtimeSettingsFile = "/mnt/runtime/config/runtime-settings.json"' in settings
    assert 'redisRelayConfigFile = "/mnt/runtime/config/redis-relay/redis-relay.toml"' in settings
    assert 'environmentFile = "/mnt/runtime/config/runtime.env"' in settings
    bootstrap = (target / "hyperv-guest/bootstrap.sh").read_text(encoding="utf-8")
    assert "VITALSERVER_REDIS_RELAY_CONFIG_DIR=/mnt/runtime/config/redis-relay" in bootstrap
    assert "VITALSERVER_REDIS_RELAY_SECRETS_DIR=/mnt/runtime/config/redis-relay-secrets" in bootstrap
    combined = json.loads(output_proof.read_text(encoding="utf-8"))
    assert combined["portableDeploy"]["status"] == "passed"
    assert combined["portableDeploy"]["mountMode"] == "native"
    assert combined["portableDeploy"]["treeSHA256"]


def test_hyperv_guest_payload_rejects_retired_request_poller(tmp_path: Path) -> None:
    system_root = tmp_path / "system-root"
    system_root.mkdir()
    deploy = tmp_path / "deploy"
    deploy.mkdir()
    (deploy / "compose.yaml").write_text("services: {}\n", encoding="utf-8")
    (deploy / "tirosh-vitalserver-command-poller").write_text("retired")
    proof = tmp_path / "rootfs-proof.json"
    proof.write_text(
        json.dumps(
            {
                "runId": "run-1",
                "dockerImages": {
                    "platform": "linux/amd64",
                    "guestArchitecture": "x86_64",
                    "status": "passed",
                },
                "cleanup": {"status": "passed"},
            }
        ),
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            sys.executable,
            str(STAGER),
            "--system-root",
            str(system_root),
            "--deploy-directory",
            str(deploy),
            "--rootfs-proof",
            str(proof),
            "--output-proof",
            str(tmp_path / "proof.json"),
        ],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert "retired v1 artifact" in result.stderr
