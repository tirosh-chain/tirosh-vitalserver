import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

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
        "tirosh-guest-tools-migrate-control-store"
    ) in control_service
    assert "--control-state-dir" not in control_service
    settings = (target / "hyperv-guest/guest-tools.toml").read_text(encoding="utf-8")
    assert 'runtimeMountMode = "native"' in settings
    assert 'vitalFilesMountMode = "native"' in settings
    assert '[controlStore]\nroot = "/mnt/runtime"\nrequiresMount = true' in settings
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


@pytest.mark.parametrize(
    ("relative", "expected_error"),
    (
        (
            "python-wheels/guest-tools/guest_tools-0.1.0-py3-none-any.whl",
            "Guest Tools wheel SHA-256 mismatch",
        ),
        (
            "python-wheels/linux-amd64/requirements.txt",
            "Guest Tools linux/amd64 requirements SHA-256 mismatch",
        ),
        (
            "python-wheels/linux-amd64/"
            "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_x86_64.whl",
            "Guest Tools linux/amd64 dependency wheel SHA-256 mismatch",
        ),
    ),
)
def test_hyperv_guest_payload_rejects_tampered_guest_tools_wheelhouse_file(
    tmp_path: Path,
    relative: str,
    expected_error: str,
) -> None:
    system_root = tmp_path / "system-root"
    system_root.mkdir()
    deploy = _write_valid_deploy(tmp_path)
    (deploy / relative).write_bytes(b"tampered")
    proof = _write_amd64_rootfs_proof(tmp_path)
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
    assert expected_error in result.stderr


@pytest.mark.parametrize(
    "dependency_wheel_name",
    (
        "alembic-1.16.0-py3-none-any.whl",
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_x86_64.whl",
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_28_x86_64.manylinux2014_x86_64.whl",
    ),
)
def test_hyperv_guest_payload_accepts_cpython312_compatible_wheels(
    tmp_path: Path,
    dependency_wheel_name: str,
) -> None:
    spec = importlib.util.spec_from_file_location("hyperv_payload_stager", STAGER)
    assert spec is not None and spec.loader is not None
    stager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stager)

    stager._require_guest_tools_runtime_payload(
        _write_valid_deploy(
            tmp_path,
            dependency_wheel_name=dependency_wheel_name,
        )
    )


@pytest.mark.parametrize(
    "dependency_wheel_name",
    (
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_aarch64.whl",
        "sqlalchemy-2.0.51-cp312-cp311-manylinux_2_17_x86_64.whl",
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_28_x86_64.whl",
        "sqlalchemy-2.0.51-cp312-cp312-linux_x86_64.whl",
    ),
)
def test_hyperv_guest_payload_rejects_incompatible_wheel_tags(
    tmp_path: Path,
    dependency_wheel_name: str,
) -> None:
    spec = importlib.util.spec_from_file_location("hyperv_payload_stager", STAGER)
    assert spec is not None and spec.loader is not None
    stager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stager)

    with pytest.raises(
        SystemExit,
        match=r"not compatible with CPython 3\.12 linux/amd64",
    ):
        stager._require_guest_tools_runtime_payload(
            _write_valid_deploy(
                tmp_path,
                dependency_wheel_name=dependency_wheel_name,
            )
        )


@pytest.mark.parametrize(
    "guest_wheel_name",
    (
        "guest_tools-0.1.0-cp312-cp312-manylinux_2_17_aarch64.whl",
        "guest_tools-0.1.0-cp312-cp311-manylinux_2_17_x86_64.whl",
        "guest_tools-0.1.0-cp312-cp312-linux_x86_64.whl",
    ),
)
def test_hyperv_guest_payload_rejects_incompatible_guest_tools_wheel(
    tmp_path: Path,
    guest_wheel_name: str,
) -> None:
    spec = importlib.util.spec_from_file_location("hyperv_payload_stager", STAGER)
    assert spec is not None and spec.loader is not None
    stager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stager)

    with pytest.raises(
        SystemExit,
        match=r"not compatible with CPython 3\.12 linux/amd64",
    ):
        stager._require_guest_tools_runtime_payload(
            _write_valid_deploy(
                tmp_path,
                guest_wheel_name=guest_wheel_name,
            )
        )


def test_hyperv_guest_payload_requires_requirements_to_pin_manifest_wheels(
    tmp_path: Path,
) -> None:
    system_root = tmp_path / "system-root"
    system_root.mkdir()
    deploy = _write_valid_deploy(tmp_path)
    wheelhouse = deploy / "python-wheels"
    manifest_path = wheelhouse / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    requirements = wheelhouse / "linux-amd64/requirements.txt"
    requirements.write_text(
        "../"
        + manifest["guestTools"]["path"]
        + " --hash=sha256:"
        + manifest["guestTools"]["sha256"]
        + "\n",
        encoding="utf-8",
    )
    manifest["targets"]["linux-amd64"]["requirementsSHA256"] = _sha256(requirements)
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    proof = _write_amd64_rootfs_proof(tmp_path)
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
    assert "requirements do not pin every manifest wheel" in result.stderr


def test_hyperv_guest_payload_ignores_hashes_in_inline_comments(
    tmp_path: Path,
) -> None:
    spec = importlib.util.spec_from_file_location("hyperv_payload_stager", STAGER)
    assert spec is not None and spec.loader is not None
    stager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stager)
    requirements = tmp_path / "requirements.txt"
    guest_hash = "a" * 64
    dependency_hash = "b" * 64
    requirements.write_text(
        "guest-tools==0.1.0 --hash=sha256:"
        + guest_hash
        + " # --hash=sha256:"
        + dependency_hash
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match="requirements do not pin every manifest wheel",
    ):
        stager._require_requirements_hash_closure(
            requirements,
            {guest_hash, dependency_hash},
        )


@pytest.mark.parametrize(
    ("requirements_text", "match"),
    [
        (
            "guest-tools==0.1.0 \\\n"
            "  # this physical line ends the continuation\n"
            "  --hash=sha256:{hash}\n",
            "not hash-pinned",
        ),
        (
            "guest-tools==0.1.0 \\ # this is not a continuation\n"
            "--hash=sha256:{hash}\n",
            "malformed line continuation",
        ),
        (
            "https://example.invalid/guest-tools.whl#--hash=sha256:{hash}\n",
            "not hash-pinned",
        ),
    ],
    ids=(
        "comment-after-continuation",
        "inline-comment-after-backslash",
        "url-fragment-is-not-option",
    ),
)
def test_hyperv_guest_payload_matches_pip_requirement_preprocessing(
    tmp_path: Path,
    requirements_text: str,
    match: str,
) -> None:
    spec = importlib.util.spec_from_file_location("hyperv_payload_stager", STAGER)
    assert spec is not None and spec.loader is not None
    stager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(stager)
    requirements = tmp_path / "requirements.txt"
    guest_hash = "a" * 64
    requirements.write_text(
        requirements_text.format(hash=guest_hash),
        encoding="utf-8",
    )

    with pytest.raises(SystemExit, match=match):
        stager._require_requirements_hash_closure(requirements, {guest_hash})


def _hyperv_inputs(tmp_path: Path) -> tuple[Path, Path, Path]:
    system_raw = tmp_path / "system.raw"
    runtime_data_raw = tmp_path / "runtime-data.raw"
    seed_iso = tmp_path / "seed.iso"
    system_raw.write_bytes(b"system")
    runtime_data_raw.write_bytes(b"runtime-data")
    seed_iso.write_bytes(b"seed")
    return system_raw, runtime_data_raw, seed_iso


def _write_valid_deploy(
    tmp_path: Path,
    *,
    guest_wheel_name: str = "guest_tools-0.1.0-py3-none-any.whl",
    dependency_wheel_name: str = (
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_x86_64.whl"
    ),
) -> Path:
    deploy = tmp_path / "deploy"
    deploy.mkdir()
    (deploy / "compose.yaml").write_text("services: {}\n", encoding="utf-8")
    for config_name in ("runtime-config.json", "runtime-settings.json", "runtime.env"):
        (deploy / config_name).write_text("configured\n", encoding="utf-8")
    (deploy / "redis-relay-config").mkdir()
    (deploy / "redis-relay-config/redis-relay.toml").write_text(
        "[redis_relay]\nenabled = false\n", encoding="utf-8"
    )
    _write_guest_control_service(deploy)
    _write_guest_tools_runtime_payload(
        deploy,
        guest_wheel_name=guest_wheel_name,
        dependency_wheel_name=dependency_wheel_name,
    )
    return deploy


def _write_amd64_rootfs_proof(tmp_path: Path) -> Path:
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
    return proof


def _write_guest_tools_runtime_payload(
    deploy: Path,
    *,
    guest_wheel_name: str = "guest_tools-0.1.0-py3-none-any.whl",
    dependency_wheel_name: str = (
        "sqlalchemy-2.0.51-cp312-cp312-manylinux_2_17_x86_64.whl"
    ),
) -> None:
    wheelhouse = deploy / "python-wheels"
    (wheelhouse / "guest-tools").mkdir(parents=True)
    (wheelhouse / "linux-amd64").mkdir()
    (deploy / "install-guest-tools-runtime.py").write_text(
        "#!/usr/bin/env python3\n",
        encoding="utf-8",
    )
    guest_wheel = wheelhouse / "guest-tools" / guest_wheel_name
    dependency_wheel = wheelhouse / "linux-amd64" / dependency_wheel_name
    requirements = wheelhouse / "linux-amd64/requirements.txt"
    guest_wheel.write_bytes(b"wheel")
    dependency_wheel.write_bytes(b"dependency-wheel")
    requirements.write_text(
        "../guest-tools/"
        + guest_wheel.name
        + " --hash=sha256:"
        + _sha256(guest_wheel)
        + "\n"
        + "sqlalchemy==2.0.51 --hash=sha256:"
        + _sha256(dependency_wheel)
        + "\n",
        encoding="utf-8",
    )
    (wheelhouse / "manifest.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "guestPython": {"major": 3, "minor": 12},
                "guestTools": {
                    "path": guest_wheel.relative_to(wheelhouse).as_posix(),
                    "sha256": _sha256(guest_wheel),
                },
                "targets": {
                    "linux-amd64": {
                        "requirementsPath": "linux-amd64/requirements.txt",
                        "requirementsSHA256": _sha256(requirements),
                        "wheels": [
                            {
                                "path": dependency_wheel.name,
                                "sha256": _sha256(dependency_wheel),
                            }
                        ],
                    }
                },
            }
        ),
        encoding="utf-8",
    )


def _sha256(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_guest_control_service(deploy: Path) -> None:
    service = deploy / "systemd/tirosh-vitalserver-guest-control-api.service"
    service.parent.mkdir()
    service.write_text(
        "[Unit]\n"
        "RequiresMountsFor=/mnt/runtime\n"
        "[Service]\n"
        "ExecStartPre=/opt/tirosh/guest-tools/venv/bin/"
        "tirosh-guest-tools-migrate-control-store\n",
        encoding="utf-8",
    )
