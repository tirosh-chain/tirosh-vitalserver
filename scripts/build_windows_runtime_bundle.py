#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "apps/vitalserver-platform-agent/packaging/windows"
AGENT = ROOT / "apps/vitalserver-platform-agent"
REQUIRED_ACCEPTANCE_STAGES = {
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
}
PACKAGING_NAMES = (
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a Windows Hyper-V Runtime v2 artifact from proved inputs."
    )
    parser.add_argument("--platform-version", required=True)
    parser.add_argument("--runtime-bundle-version", required=True)
    parser.add_argument("--agent-binary", type=Path, required=True)
    parser.add_argument("--provider-binary", type=Path, required=True)
    parser.add_argument("--pwa-directory", type=Path, required=True)
    parser.add_argument("--hyperv-image-directory", type=Path, required=True)
    parser.add_argument("--acceptance-manifest", type=Path)
    parser.add_argument(
        "--acceptance-candidate",
        action="store_true",
        help=(
            "Build the explicitly unsealed candidate used only to produce "
            "installed acceptance evidence."
        ),
    )
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.acceptance_candidate == (args.acceptance_manifest is not None):
        raise SystemExit(
            "choose exactly one of --acceptance-candidate or --acceptance-manifest"
        )
    _validate_version(args.platform_version, "platform version")
    _validate_version(args.runtime_bundle_version, "Runtime Bundle version")
    _require_windows_amd64_pe(args.agent_binary, "Platform Agent")
    _require_windows_amd64_pe(args.provider_binary, "Hyper-V Runtime Provider")
    _require_file(args.pwa_directory / "index.html", "PWA index")
    _require_tree_without_symlinks(args.pwa_directory, "PWA")
    image_manifest_path = args.hyperv_image_directory / "hyperv-image.json"
    image_manifest = _load_json(image_manifest_path, "Hyper-V image manifest")
    _validate_image_manifest(image_manifest, args.hyperv_image_directory)
    support_files = {
        **{
            "packaging/" + name: (PACKAGING / name).read_bytes()
            for name in PACKAGING_NAMES
        },
        "config/platform-agent.example.json": (
            AGENT / "config.windows.example.json"
        ).read_bytes(),
        "config/hyperv-provider.example.json": (
            AGENT / "config.windows-hyperv-provider.example.json"
        ).read_bytes(),
    }
    release_inputs = {
        "platformAgentSHA256": _sha256(args.agent_binary),
        "runtimeProviderSHA256": _sha256(args.provider_binary),
        "pwaTreeSHA256": _tree_sha256(args.pwa_directory),
        "hyperVImageManifestSHA256": _sha256(image_manifest_path),
        "packagingTreeSHA256": _files_tree_sha256(support_files),
    }
    acceptance_candidate_release = {
        "schemaVersion": 1,
        "state": "acceptanceCandidate",
        "platformVersion": args.platform_version,
        "runtimeBundleVersion": args.runtime_bundle_version,
        "target": {"os": "windows", "architecture": "amd64", "provider": "hyperv"},
        "imageCompileRunId": image_manifest["runId"],
        "installedAcceptanceRunId": None,
        "inputs": release_inputs,
    }
    acceptance = None
    if args.acceptance_manifest is not None:
        acceptance = _load_json(args.acceptance_manifest, "Windows acceptance manifest")
        _validate_acceptance(
            acceptance,
            expected_image_manifest_sha256=_sha256(image_manifest_path),
            expected_platform_version=args.platform_version,
            expected_runtime_bundle_version=args.runtime_bundle_version,
            expected_release_inputs=release_inputs,
            expected_release_manifest_sha256=hashlib.sha256(
                _release_bytes(acceptance_candidate_release)
            ).hexdigest(),
        )

    release = (
        acceptance_candidate_release
        if acceptance is None
        else {
            "schemaVersion": 1,
            "state": "releaseCandidate",
            "platformVersion": args.platform_version,
            "runtimeBundleVersion": args.runtime_bundle_version,
            "target": {"os": "windows", "architecture": "amd64", "provider": "hyperv"},
            "imageCompileRunId": image_manifest["runId"],
            "installedAcceptanceRunId": acceptance["runId"],
            "inputs": {
                **release_inputs,
                "acceptanceManifestSHA256": _sha256(args.acceptance_manifest),
            },
        }
    )
    files: dict[str, bytes] = {
        "VERSION": (args.platform_version + "\n").encode(),
        "RUNTIME_BUNDLE_VERSION": (args.runtime_bundle_version + "\n").encode(),
        "release.json": _release_bytes(release),
        "bin/vitalserver-platform-agent.exe": args.agent_binary.read_bytes(),
        "bin/vitalserver-hyperv-runtime-provider.exe": (
            args.provider_binary.read_bytes()
        ),
    }
    if acceptance is None:
        files["proof/acceptance-pending.json"] = (
            json.dumps(
                {
                    "schemaVersion": 1,
                    "state": "pending",
                    "reason": (
                        "This acceptanceCandidate is not a distributable release; "
                        "run installed Hyper-V acceptance and seal a releaseCandidate."
                    ),
                },
                indent=2,
                sort_keys=True,
            )
            + "\n"
        ).encode()
    else:
        files["proof/windows-hyperv-acceptance.json"] = (
            args.acceptance_manifest.read_bytes()
        )
    for path in sorted(
        item for item in args.pwa_directory.rglob("*") if item.is_file()
    ):
        relative = path.relative_to(args.pwa_directory).as_posix()
        files["pwa/" + relative] = path.read_bytes()
    for path in sorted(
        item for item in args.hyperv_image_directory.rglob("*") if item.is_file()
    ):
        relative = path.relative_to(args.hyperv_image_directory).as_posix()
        files["hyperv-image/" + relative] = path.read_bytes()
    files.update(support_files)
    checksum_text = "".join(
        f"{hashlib.sha256(data).hexdigest()}  {name}\n"
        for name, data in sorted(files.items())
    )
    files["checksums.sha256"] = checksum_text.encode()
    _write_deterministic_zip(args.output, files)
    candidate_kind = (
        "acceptance candidate" if acceptance is None else "sealed release candidate"
    )
    print(f"Windows Runtime v2 {candidate_kind}: {args.output}")
    return 0


def _validate_version(value: str, label: str) -> None:
    if not value or any(
        not (character.isalnum() or character in "._+-") for character in value
    ):
        raise SystemExit(f"{label} is invalid: {value!r}")


def _require_windows_amd64_pe(path: Path, label: str) -> None:
    _require_file(path, label)
    data = path.read_bytes()
    if len(data) < 64 or data[:2] != b"MZ":
        raise SystemExit(f"{label} is not a PE executable: {path}")
    offset = struct.unpack_from("<I", data, 0x3C)[0]
    if offset + 6 > len(data) or data[offset : offset + 4] != b"PE\0\0":
        raise SystemExit(f"{label} has no valid PE header: {path}")
    machine = struct.unpack_from("<H", data, offset + 4)[0]
    if machine != 0x8664:
        raise SystemExit(
            f"{label} must target windows/amd64 machine=0x8664 "
            f"actual=0x{machine:04x}: {path}"
        )


def _validate_image_manifest(document: dict[str, object], root: Path) -> None:
    if (
        document.get("schemaVersion") != 1
        or document.get("state") != "compiled"
        or document.get("architecture") != "amd64"
        or not isinstance(document.get("runId"), str)
        or document.get("readError") is not None
    ):
        raise SystemExit("Hyper-V image manifest is not a compiled amd64 contract")
    for field in ("systemVHDX", "runtimeDataVHDX", "seedISO"):
        artifact = document.get(field)
        if not isinstance(artifact, dict):
            raise SystemExit(f"Hyper-V image manifest field is missing: {field}")
        relative = artifact.get("path")
        expected = artifact.get("sha256")
        if not isinstance(relative, str) or not isinstance(expected, str):
            raise SystemExit(f"Hyper-V image manifest artifact is invalid: {field}")
        relative_path = PurePosixPath(relative)
        if (
            relative_path.is_absolute()
            or len(relative_path.parts) != 1
            or relative_path.name != relative
        ):
            raise SystemExit(
                f"Hyper-V image manifest artifact path is unsafe: {field}={relative!r}"
            )
        path = root / relative
        _require_file(path, f"Hyper-V {field}")
        actual = _sha256(path)
        if actual != expected:
            raise SystemExit(
                f"Hyper-V image artifact checksum mismatch field={field} "
                f"expected={expected} actual={actual}"
            )


def _validate_acceptance(
    document: dict[str, object],
    *,
    expected_image_manifest_sha256: str,
    expected_platform_version: str,
    expected_runtime_bundle_version: str,
    expected_release_inputs: dict[str, str],
    expected_release_manifest_sha256: str,
) -> None:
    if (
        document.get("schemaVersion") != 1
        or document.get("platform") != "windows-hyperv-amd64"
        or document.get("status") != "passed"
        or not isinstance(document.get("runId"), str)
        or document.get("failureStage") is not None
        or document.get("failureReason") is not None
        or document.get("platformVersion") != expected_platform_version
        or document.get("runtimeBundleVersion") != expected_runtime_bundle_version
        or not isinstance(document.get("hostBootSessionId"), str)
        or not document.get("hostBootSessionId")
    ):
        raise SystemExit("Windows Hyper-V acceptance manifest is not passed")
    if document.get("hyperVImageManifestSHA256") != expected_image_manifest_sha256:
        raise SystemExit(
            "Windows acceptance manifest does not prove this Hyper-V image"
        )
    if document.get("releaseInputs") != expected_release_inputs:
        raise SystemExit(
            "Windows acceptance manifest does not prove these release component inputs"
        )
    if document.get("releaseManifestSHA256") != expected_release_manifest_sha256:
        raise SystemExit(
            "Windows acceptance manifest does not prove the acceptanceCandidate "
            "release manifest"
        )
    if document.get("supportExportMode") != "execute":
        raise SystemExit(
            "Windows sealing acceptance manifest must execute support export"
        )
    support_export_operation_id = document.get("supportExportOperationId")
    support_artifact_sha256 = document.get("supportArtifactSHA256")
    support_artifact_size_bytes = document.get("supportArtifactSizeBytes")
    if (
        not isinstance(support_export_operation_id, str)
        or not support_export_operation_id
        or not isinstance(support_artifact_sha256, str)
        or len(support_artifact_sha256) != 64
        or any(
            character not in "0123456789abcdef"
            for character in support_artifact_sha256
        )
        or not isinstance(support_artifact_size_bytes, int)
        or isinstance(support_artifact_size_bytes, bool)
        or support_artifact_size_bytes <= 0
    ):
        raise SystemExit(
            "Windows acceptance manifest has no valid support artifact evidence"
        )
    stages = document.get("stages")
    if not isinstance(stages, list):
        raise SystemExit("Windows acceptance manifest stages are missing")
    passed = {
        stage.get("name")
        for stage in stages
        if isinstance(stage, dict) and stage.get("status") == "passed"
    }
    missing = sorted(REQUIRED_ACCEPTANCE_STAGES - passed)
    if missing:
        raise SystemExit(
            "Windows acceptance manifest misses passed stages: " + ", ".join(missing)
        )


def _load_json(path: Path, label: str) -> dict[str, object]:
    _require_file(path, label)
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"{label} decode failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"{label} must be a JSON object: {path}")
    return value


def _release_bytes(document: dict[str, object]) -> bytes:
    return (json.dumps(document, indent=2, sort_keys=True) + "\n").encode()


def _require_file(path: Path, label: str) -> None:
    if not path.is_file():
        raise SystemExit(f"{label} is missing: {path}")


def _require_tree_without_symlinks(path: Path, label: str) -> None:
    if not path.is_dir():
        raise SystemExit(f"{label} directory is missing: {path}")
    for item in path.rglob("*"):
        if item.is_symlink():
            raise SystemExit(f"{label} contains unsupported symlink: {item}")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix().encode()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(bytes.fromhex(_sha256(path)))
    return digest.hexdigest()


def _files_tree_sha256(files: dict[str, bytes]) -> str:
    digest = hashlib.sha256()
    for name, data in sorted(files.items()):
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(len(data)).encode("ascii"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(data).digest())
    return digest.hexdigest()


def _write_deterministic_zip(output: Path, files: dict[str, bytes]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    with zipfile.ZipFile(
        temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo("VitalServer-Windows/" + name)
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.create_system = 0
            info.external_attr = 0
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    temporary.replace(output)


if __name__ == "__main__":
    raise SystemExit(main())
