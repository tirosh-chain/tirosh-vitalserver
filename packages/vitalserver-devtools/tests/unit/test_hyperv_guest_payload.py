import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
STAGER = ROOT / "scripts/stage_hyperv_guest_payload.py"


def test_hyperv_guest_payload_stages_native_owner_contract(tmp_path: Path) -> None:
    system_root = tmp_path / "system-root"
    system_root.mkdir()
    deploy = tmp_path / "deploy"
    deploy.mkdir()
    (deploy / "compose.yaml").write_text(
        "services:\n"
        "  controller:\n"
        "    environment:\n"
        "      URL: /runtime/capabilities\n",
        encoding="utf-8",
    )
    for config_name in ("runtime-config.json", "runtime-settings.json", "runtime.env"):
        (deploy / config_name).write_text("configured\n", encoding="utf-8")
    (deploy / "redis-relay-config").mkdir()
    (deploy / "redis-relay-config/redis-relay.toml").write_text(
        "[redis_relay]\nenabled = false\n", encoding="utf-8"
    )
    _write_guest_control_service(deploy)
    _write_guest_tools_runtime_payload(deploy)
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
    system_raw, data_raw, seed_iso = _hyperv_inputs(tmp_path)
    output_proof = tmp_path / "hyperv-proof.json"

    subprocess.run(
        [
            sys.executable,
            str(STAGER),
            "--system-root",
            str(system_root),
            "--system-raw",
            str(system_raw),
            "--runtime-data-raw",
            str(data_raw),
            "--seed-iso",
            str(seed_iso),
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
    assert (target / "deploy/install-guest-tools-runtime.py").is_file()
    assert (target / "deploy/python-wheels/manifest.json").is_file()
    control_service = (
        target / "deploy/systemd/tirosh-vitalserver-guest-control-api.service"
    ).read_text(encoding="utf-8")
    assert "RequiresMountsFor=/mnt/runtime" in control_service
    assert (
        "ExecStartPre=/opt/tirosh/guest-tools/venv/bin/"
        "tirosh-guest-tools-migrate-control-store --control-state-dir "
        "/mnt/runtime/control"
    ) in control_service
    settings = (target / "hyperv-guest/guest-tools.toml").read_text(encoding="utf-8")
    assert 'runtimeMountMode = "native"' in settings
    assert 'vitalFilesMountMode = "native"' in settings
    assert 'runtimeConfigFile = "/mnt/runtime/config/runtime-config.json"' in settings
    assert (
        'runtimeSettingsFile = "/mnt/runtime/config/runtime-settings.json"' in settings
    )
    assert (
        'redisRelayConfigFile = "/mnt/runtime/config/redis-relay/redis-relay.toml"'
        in settings
    )
    assert 'environmentFile = "/mnt/runtime/config/runtime.env"' in settings
    bootstrap = (target / "hyperv-guest/bootstrap.sh").read_text(encoding="utf-8")
    assert (
        "VITALSERVER_REDIS_RELAY_CONFIG_DIR=/mnt/runtime/config/redis-relay"
        in bootstrap
    )
    assert (
        "VITALSERVER_REDIS_RELAY_SECRETS_DIR=/mnt/runtime/config/redis-relay-secrets"
        in bootstrap
    )
    combined = json.loads(output_proof.read_text(encoding="utf-8"))
    assert combined["portableDeploy"]["status"] == "passed"
    assert combined["portableDeploy"]["mountMode"] == "native"
    assert combined["portableDeploy"]["treeSHA256"]
    assert combined["portableDeploy"]["hyperVInputs"]["systemRaw"]["sha256"]
    assert combined["portableDeploy"]["hyperVInputs"]["runtimeDataRaw"]["sha256"]
    assert combined["portableDeploy"]["hyperVInputs"]["seedISO"]["sha256"]


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
    system_raw, data_raw, seed_iso = _hyperv_inputs(tmp_path)
    result = subprocess.run(
        [
            sys.executable,
            str(STAGER),
            "--system-root",
            str(system_root),
            "--system-raw",
            str(system_raw),
            "--runtime-data-raw",
            str(data_raw),
            "--seed-iso",
            str(seed_iso),
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


def _hyperv_inputs(tmp_path: Path) -> tuple[Path, Path, Path]:
    system_raw = tmp_path / "system.raw"
    runtime_data_raw = tmp_path / "runtime-data.raw"
    seed_iso = tmp_path / "seed.iso"
    system_raw.write_bytes(b"system")
    runtime_data_raw.write_bytes(b"runtime-data")
    seed_iso.write_bytes(b"seed")
    return system_raw, runtime_data_raw, seed_iso


def _write_guest_tools_runtime_payload(deploy: Path) -> None:
    wheelhouse = deploy / "python-wheels"
    (wheelhouse / "guest-tools").mkdir(parents=True)
    (wheelhouse / "linux-amd64").mkdir()
    (deploy / "install-guest-tools-runtime.py").write_text(
        "#!/usr/bin/env python3\n",
        encoding="utf-8",
    )
    (wheelhouse / "guest-tools/guest-tools.whl").write_bytes(b"wheel")
    (wheelhouse / "linux-amd64/sqlalchemy.whl").write_bytes(b"wheel")
    (wheelhouse / "linux-amd64/requirements.txt").write_text(
        "guest-tools\n",
        encoding="utf-8",
    )
    (wheelhouse / "manifest.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "guestTools": {"path": "guest-tools/guest-tools.whl"},
                "targets": {
                    "linux-amd64": {
                        "requirementsPath": "linux-amd64/requirements.txt"
                    }
                },
            }
        ),
        encoding="utf-8",
    )


def _write_guest_control_service(deploy: Path) -> None:
    service = deploy / "systemd/tirosh-vitalserver-guest-control-api.service"
    service.parent.mkdir()
    service.write_text(
        "[Unit]\n"
        "RequiresMountsFor=/mnt/runtime\n"
        "[Service]\n"
        "ExecStartPre=/opt/tirosh/guest-tools/venv/bin/"
        "tirosh-guest-tools-migrate-control-store --control-state-dir "
        "/mnt/runtime/control\n",
        encoding="utf-8",
    )
