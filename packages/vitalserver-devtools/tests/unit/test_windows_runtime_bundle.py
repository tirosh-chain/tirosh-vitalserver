import hashlib
import json
import runpy
import struct
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[4]
BUILDER = ROOT / "scripts/build_windows_runtime_bundle.py"


def test_windows_builder_requires_exactly_one_proof_phase(tmp_path: Path) -> None:
    common = [
        sys.executable, str(BUILDER),
        "--platform-version", "2.0.0",
        "--runtime-bundle-version", "2.3.4",
        "--agent-binary", str(tmp_path / "agent.exe"),
        "--provider-binary", str(tmp_path / "provider.exe"),
        "--pwa-directory", str(tmp_path / "pwa"),
        "--hyperv-image-directory", str(tmp_path / "image"),
        "--output", str(tmp_path / "output.zip"),
    ]
    missing = subprocess.run(common, capture_output=True, text=True)
    both = subprocess.run(
        [*common, "--acceptance-candidate", "--acceptance-manifest", str(tmp_path / "proof.json")],
        capture_output=True,
        text=True,
    )
    assert missing.returncode != 0
    assert both.returncode != 0
    assert "choose exactly one" in missing.stderr
    assert "choose exactly one" in both.stderr


def test_windows_bundle_requires_image_bound_acceptance_and_is_deterministic(
    tmp_path: Path,
) -> None:
    agent = tmp_path / "agent.exe"
    provider = tmp_path / "provider.exe"
    _write_amd64_pe(agent)
    _write_amd64_pe(provider)
    pwa = tmp_path / "pwa"
    pwa.mkdir()
    (pwa / "index.html").write_text("pwa", encoding="utf-8")
    image = tmp_path / "image"
    image.mkdir()
    artifacts = {
        "systemVHDX": "system.vhdx",
        "runtimeDataVHDX": "data.vhdx",
        "seedISO": "seed.iso",
    }
    image_manifest: dict[str, object] = {
        "schemaVersion": 1,
        "state": "compiled",
        "runId": "compile-run-1",
        "architecture": "amd64",
        "readError": None,
    }
    for field, name in artifacts.items():
        path = image / name
        path.write_bytes(field.encode())
        image_manifest[field] = {
            "path": name,
            "sha256": _sha256(path),
            "bytes": path.stat().st_size,
        }
    image_manifest_path = image / "hyperv-image.json"
    image_manifest_path.write_text(
        json.dumps(image_manifest, sort_keys=True), encoding="utf-8"
    )
    candidate = tmp_path / "acceptance-candidate.zip"
    subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--platform-version", "2.0.0",
            "--runtime-bundle-version", "2.3.4",
            "--agent-binary", str(agent),
            "--provider-binary", str(provider),
            "--pwa-directory", str(pwa),
            "--hyperv-image-directory", str(image),
            "--acceptance-candidate",
            "--output", str(candidate),
        ],
        check=True,
    )
    with zipfile.ZipFile(candidate) as archive:
        candidate_release_bytes = archive.read("VitalServer-Windows/release.json")
        candidate_release = json.loads(candidate_release_bytes)
        assert candidate_release["state"] == "acceptanceCandidate"
        assert candidate_release["installedAcceptanceRunId"] is None
        assert "VitalServer-Windows/proof/acceptance-pending.json" in archive.namelist()
        assert "VitalServer-Windows/proof/windows-hyperv-acceptance.json" not in archive.namelist()

    packaging_tree_sha256 = _packaging_tree_sha256()
    acceptance = tmp_path / "acceptance.json"
    acceptance.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": "acceptance-run-1",
                "platform": "windows-hyperv-amd64",
                "platformVersion": "2.0.0",
                "runtimeBundleVersion": "2.3.4",
                "hostBootSessionId": "2026-07-11T00:00:00.0000000Z",
                "releaseInputs": {
                    "platformAgentSHA256": _sha256(agent),
                    "runtimeProviderSHA256": _sha256(provider),
                    "pwaTreeSHA256": _tree_sha256(pwa),
                    "hyperVImageManifestSHA256": _sha256(image_manifest_path),
                    "packagingTreeSHA256": packaging_tree_sha256,
                },
                "releaseManifestSHA256": hashlib.sha256(candidate_release_bytes).hexdigest(),
                "supportExportMode": "execute",
                "supportExportOperationId": "support-operation-1",
                "supportArtifactSHA256": "a" * 64,
                "supportArtifactSizeBytes": 42,
                "status": "passed",
                "failureStage": None,
                "failureReason": None,
                "hyperVImageManifestSHA256": _sha256(image_manifest_path),
                "stages": [
                    {"name": name, "status": "passed"}
                    for name in (
                        "preflight",
                        "runtime-provider-running",
                        "platform-contract",
                        "runtime-capabilities",
                        "runtime-services",
                        "runtime-stack",
                        "runtime-settings",
                        "redis-relay-settings",
                        "runtime-events",
                        "product-pwa",
                        "platform-support-export",
                        "runtime-provider-stop",
                        "runtime-provider-start",
                        "runtime-after-provider-restart",
                    )
                ],
            }
        ),
        encoding="utf-8",
    )
    first = tmp_path / "first.zip"
    second = tmp_path / "second.zip"

    for output in (first, second):
        subprocess.run(
            [
                sys.executable,
                str(BUILDER),
                "--platform-version",
                "2.0.0",
                "--runtime-bundle-version",
                "2.3.4",
                "--agent-binary",
                str(agent),
                "--provider-binary",
                str(provider),
                "--pwa-directory",
                str(pwa),
                "--hyperv-image-directory",
                str(image),
                "--acceptance-manifest",
                str(acceptance),
                "--output",
                str(output),
            ],
            check=True,
        )

    assert _sha256(first) == _sha256(second)
    with zipfile.ZipFile(first) as archive:
        names = set(archive.namelist())
        release = json.loads(archive.read("VitalServer-Windows/release.json"))
        assert release["state"] == "releaseCandidate"
        assert release["installedAcceptanceRunId"] == "acceptance-run-1"
        assert release["inputs"]["packagingTreeSHA256"] == packaging_tree_sha256
        assert {
            "VitalServer-Windows/release.json",
            "VitalServer-Windows/checksums.sha256",
            "VitalServer-Windows/bin/vitalserver-platform-agent.exe",
            "VitalServer-Windows/bin/vitalserver-hyperv-runtime-provider.exe",
            "VitalServer-Windows/hyperv-image/hyperv-image.json",
            "VitalServer-Windows/proof/windows-hyperv-acceptance.json",
            "VitalServer-Windows/packaging/acceptance-clean-uninstall-hyperv.ps1",
            "VitalServer-Windows/packaging/provision-hyperv.ps1",
            "VitalServer-Windows/packaging/install-service.ps1",
            "VitalServer-Windows/packaging/install-windows.ps1",
            "VitalServer-Windows/packaging/acceptance-reboot-hyperv.ps1",
            "VitalServer-Windows/packaging/acceptance-uninstall-reinstall-hyperv.ps1",
            "VitalServer-Windows/packaging/acceptance-update-rollback-hyperv.ps1",
            "VitalServer-Windows/packaging/schedule-workflow-windows.ps1",
            "VitalServer-Windows/packaging/update-windows.ps1",
            "VitalServer-Windows/packaging/apply-update-windows.ps1",
            "VitalServer-Windows/packaging/rollback-windows.ps1",
            "VitalServer-Windows/packaging/uninstall-windows.ps1",
            "VitalServer-Windows/packaging/support-export-windows.ps1",
            "VitalServer-Windows/packaging/windows-delivery.psm1",
            "VitalServer-Windows/packaging/trust-update-windows.ps1",
        }.issubset(names)


def test_windows_support_export_uses_managed_artifact_contract() -> None:
    script = (
        ROOT / "apps/vitalserver-platform-agent/packaging/windows/support-export-windows.ps1"
    ).read_text(encoding="utf-8")
    assert "kind = 'support-export'" in script
    assert "artifact = $Artifact" in script
    assert "Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256" in script
    assert "sizeBytes = [Int64]$file.Length" in script
    assert "config\\platform-agent.json" in script
    assert "secrets" in script
    assert "Copy-Item -LiteralPath $source" in script
    assert "Protect-OwnerPath -Path $supportRoot -Directory" in script
    assert "Protect-OwnerPath -Path $destination" in script
    assert "provision.vmName" in script
    assert "install.vmName" not in script


def test_windows_candidate_is_installable_only_for_acceptance_and_not_update() -> None:
    installer = (
        ROOT / "apps/vitalserver-platform-agent/packaging/windows/install-windows.ps1"
    ).read_text(encoding="utf-8")
    delivery = (
        ROOT / "apps/vitalserver-platform-agent/packaging/windows/windows-delivery.psm1"
    ).read_text(encoding="utf-8")
    acceptance = (
        ROOT / "apps/vitalserver-platform-agent/packaging/windows/acceptance-hyperv.ps1"
    ).read_text(encoding="utf-8")
    assert "@('acceptanceCandidate', 'releaseCandidate')" in installer
    assert "$release.state -ne 'releaseCandidate'" in delivery
    assert "packagingTreeSHA256" in acceptance


def test_windows_bundle_rejects_acceptance_for_another_image(tmp_path: Path) -> None:
    invalid = tmp_path / "invalid.exe"
    _write_amd64_pe(invalid)
    pwa = tmp_path / "pwa"
    pwa.mkdir()
    (pwa / "index.html").write_text("pwa")
    image = tmp_path / "image"
    image.mkdir()
    for name in ("system.vhdx", "data.vhdx", "seed.iso"):
        (image / name).write_bytes(name.encode())
    manifest = {
        "schemaVersion": 1,
        "state": "compiled",
        "runId": "compile",
        "architecture": "amd64",
        "readError": None,
        "systemVHDX": {"path": "system.vhdx", "sha256": _sha256(image / "system.vhdx")},
        "runtimeDataVHDX": {"path": "data.vhdx", "sha256": _sha256(image / "data.vhdx")},
        "seedISO": {"path": "seed.iso", "sha256": _sha256(image / "seed.iso")},
    }
    (image / "hyperv-image.json").write_text(json.dumps(manifest))
    acceptance = tmp_path / "acceptance.json"
    acceptance.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": "acceptance",
                "platform": "windows-hyperv-amd64",
                "platformVersion": "2.0.0",
                "runtimeBundleVersion": "2.3.4",
                "hostBootSessionId": "2026-07-11T00:00:00.0000000Z",
                "status": "passed",
                "failureStage": None,
                "failureReason": None,
                "hyperVImageManifestSHA256": "another-image",
                "stages": [],
            }
        )
    )
    result = subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--platform-version",
            "2.0.0",
            "--runtime-bundle-version",
            "2.3.4",
            "--agent-binary",
            str(invalid),
            "--provider-binary",
            str(invalid),
            "--pwa-directory",
            str(pwa),
            "--hyperv-image-directory",
            str(image),
            "--acceptance-manifest",
            str(acceptance),
            "--output",
            str(tmp_path / "bundle.zip"),
        ],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert "does not prove this Hyper-V image" in result.stderr


@pytest.mark.parametrize(
    ("field", "value"),
    (
        ("supportArtifactSHA256", ["not", "a", "digest"]),
        ("supportArtifactSHA256", 42),
        ("supportArtifactSizeBytes", "42"),
        ("supportArtifactSizeBytes", True),
    ),
)
def test_windows_bundle_rejects_malformed_support_artifact_evidence(
    field: str,
    value: object,
) -> None:
    module = runpy.run_path(str(BUILDER), run_name="windows_runtime_bundle")
    validate_acceptance = module["_validate_acceptance"]
    assert callable(validate_acceptance)
    release_inputs = {"component": "digest"}
    document: dict[str, object] = {
        "schemaVersion": 1,
        "platform": "windows-hyperv-amd64",
        "status": "passed",
        "runId": "acceptance-run-1",
        "failureStage": None,
        "failureReason": None,
        "platformVersion": "2.0.0",
        "runtimeBundleVersion": "2.3.4",
        "hostBootSessionId": "boot-session-1",
        "hyperVImageManifestSHA256": "image-digest",
        "releaseInputs": release_inputs,
        "releaseManifestSHA256": "release-digest",
        "supportExportMode": "execute",
        "supportExportOperationId": "support-operation-1",
        "supportArtifactSHA256": "a" * 64,
        "supportArtifactSizeBytes": 42,
        "stages": [],
    }
    document[field] = value

    with pytest.raises(
        SystemExit,
        match="Windows acceptance manifest has no valid support artifact evidence",
    ):
        validate_acceptance(
            document,
            expected_image_manifest_sha256="image-digest",
            expected_platform_version="2.0.0",
            expected_runtime_bundle_version="2.3.4",
            expected_release_inputs=release_inputs,
            expected_release_manifest_sha256="release-digest",
        )


def test_windows_bundle_rejects_image_artifact_path_escape(tmp_path: Path) -> None:
    invalid = tmp_path / "invalid.exe"
    _write_amd64_pe(invalid)
    pwa = tmp_path / "pwa"
    pwa.mkdir()
    (pwa / "index.html").write_text("pwa")
    image = tmp_path / "image"
    image.mkdir()
    for name in ("system.vhdx", "data.vhdx", "seed.iso"):
        (image / name).write_bytes(name.encode())
    outside = tmp_path / "outside.vhdx"
    outside.write_bytes(b"outside")
    manifest = {
        "schemaVersion": 1,
        "state": "compiled",
        "runId": "compile",
        "architecture": "amd64",
        "readError": None,
        "systemVHDX": {"path": "../outside.vhdx", "sha256": _sha256(outside)},
        "runtimeDataVHDX": {"path": "data.vhdx", "sha256": _sha256(image / "data.vhdx")},
        "seedISO": {"path": "seed.iso", "sha256": _sha256(image / "seed.iso")},
    }
    image_manifest = image / "hyperv-image.json"
    image_manifest.write_text(json.dumps(manifest))
    acceptance = tmp_path / "acceptance.json"
    acceptance.write_text(json.dumps({
        "schemaVersion": 1,
        "runId": "acceptance",
        "platform": "windows-hyperv-amd64",
        "platformVersion": "2.0.0",
        "runtimeBundleVersion": "2.3.4",
        "hostBootSessionId": "2026-07-11T00:00:00Z",
        "status": "passed",
        "failureStage": None,
        "failureReason": None,
        "hyperVImageManifestSHA256": _sha256(image_manifest),
        "stages": [],
    }))
    result = subprocess.run([
        sys.executable, str(BUILDER),
        "--platform-version", "2.0.0",
        "--runtime-bundle-version", "2.3.4",
        "--agent-binary", str(invalid),
        "--provider-binary", str(invalid),
        "--pwa-directory", str(pwa),
        "--hyperv-image-directory", str(image),
        "--acceptance-manifest", str(acceptance),
        "--output", str(tmp_path / "bundle.zip"),
    ], text=True, capture_output=True)

    assert result.returncode != 0
    assert "artifact path is unsafe" in result.stderr


def _write_amd64_pe(path: Path) -> None:
    data = bytearray(256)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 128)
    data[128:132] = b"PE\0\0"
    struct.pack_into("<H", data, 132, 0x8664)
    path.write_bytes(data)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(bytes.fromhex(_sha256(path)))
    return digest.hexdigest()


def _packaging_tree_sha256() -> str:
    packaging = ROOT / "apps/vitalserver-platform-agent/packaging/windows"
    agent = ROOT / "apps/vitalserver-platform-agent"
    names = (
        "acceptance-clean-uninstall-hyperv.ps1",
        "acceptance-hyperv.ps1",
        "acceptance-reboot-hyperv.ps1",
        "acceptance-uninstall-reinstall-hyperv.ps1",
        "acceptance-update-rollback-hyperv.ps1",
        "apply-update-windows.ps1",
        "install-service.ps1",
        "install-windows.ps1",
        "provision-hyperv.ps1",
        "rollback-windows.ps1",
        "support-export-windows.ps1",
        "trust-update-windows.ps1",
        "uninstall-windows.ps1",
        "schedule-workflow-windows.ps1",
        "update-windows.ps1",
        "windows-delivery.psm1",
    )
    files = {
        **{"packaging/" + name: (packaging / name).read_bytes() for name in names},
        "config/platform-agent.example.json": (agent / "config.windows.example.json").read_bytes(),
        "config/hyperv-provider.example.json": (agent / "config.windows-hyperv-provider.example.json").read_bytes(),
    }
    digest = hashlib.sha256()
    for name, data in sorted(files.items()):
        digest.update(name.encode())
        digest.update(b"\0")
        digest.update(str(len(data)).encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(data).digest())
    return digest.hexdigest()
