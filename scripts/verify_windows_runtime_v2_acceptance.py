#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import UTC, datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
from typing import Any
import zipfile


ROOT = "VitalServer-Windows"
RUNTIME_STAGES = {
    "preflight", "runtime-provider-running", "platform-contract", "runtime-capabilities",
    "runtime-services", "runtime-stack", "runtime-settings", "redis-relay-settings",
    "runtime-events", "product-pwa", "platform-support-export", "runtime-provider-stop",
    "runtime-provider-start", "runtime-after-provider-restart",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify one explicit Windows Runtime v2 lifecycle evidence chain.")
    parser.add_argument("--sealed-bundle", type=Path, required=True)
    parser.add_argument("--clean-host-acceptance", type=Path, required=True)
    parser.add_argument("--reboot-proof", type=Path, required=True)
    parser.add_argument("--reboot-runtime-acceptance", type=Path, required=True)
    parser.add_argument("--update-bundle", type=Path, required=True)
    parser.add_argument("--update-rollback-proof", type=Path, required=True)
    parser.add_argument("--uninstall-reinstall-proof", type=Path, required=True)
    parser.add_argument("--clean-uninstall-proof", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    base = load_bundle(args.sealed_bundle)
    update = load_bundle(args.update_bundle)
    clean_host = load_json(args.clean_host_acceptance, "clean-host acceptance")
    reboot = load_json(args.reboot_proof, "reboot proof")
    reboot_runtime = load_json(args.reboot_runtime_acceptance, "post-reboot Runtime acceptance")
    update_rollback = load_json(args.update_rollback_proof, "update/rollback proof")
    uninstall_reinstall = load_json(args.uninstall_reinstall_proof, "uninstall/reinstall proof")
    clean_uninstall = load_json(args.clean_uninstall_proof, "clean uninstall proof")

    base_release = base["release"]
    update_release = update["release"]
    if base_release["platformVersion"] == update_release["platformVersion"]:
        fail("update bundle platformVersion must differ from the original sealed bundle")
    validate_runtime_acceptance(clean_host, base, "clean-host acceptance")
    if clean_host["runId"] == base_release["installedAcceptanceRunId"]:
        fail("clean-host acceptance must be a new run, not the sealing acceptance")
    validate_runtime_acceptance(reboot_runtime, base, "post-reboot Runtime acceptance")

    validate_proof(reboot, "reboot", {"preflight", "boot-session-changed", "installed-runtime-acceptance"})
    require_release(reboot, base, "reboot proof")
    require_equal(reboot, "installedAcceptanceRunId", clean_host["runId"], "reboot proof")
    require_equal(reboot, "runtimeAcceptanceRunId", reboot_runtime["runId"], "reboot proof")
    if reboot.get("installedBootSessionId") == reboot.get("currentBootSessionId"):
        fail("reboot proof does not show a changed boot session")
    require_equal(reboot_runtime, "hostBootSessionId", reboot["currentBootSessionId"], "post-reboot Runtime acceptance")

    validate_proof(
        update_rollback,
        "update-rollback-data-preservation",
        {"preflight", "runtime-data-marker-applied", "update-accepted", "update-completed",
         "update-data-preserved", "rollback-accepted", "rollback-completed",
         "rollback-data-preserved", "runtime-settings-restored"},
    )
    require_equal(update_rollback, "originalPlatformVersion", base_release["platformVersion"], "update/rollback proof")
    require_equal(update_rollback, "originalRuntimeBundleVersion", base_release["runtimeBundleVersion"], "update/rollback proof")
    require_equal(update_rollback, "updatePlatformVersion", update_release["platformVersion"], "update/rollback proof")
    require_equal(update_rollback, "updateRuntimeBundleVersion", update_release["runtimeBundleVersion"], "update/rollback proof")
    require_equal(update_rollback, "beforeInstalledAcceptanceRunId", clean_host["runId"], "update/rollback proof")
    require_equal(update_rollback, "originalReleaseManifestSHA256", base["releaseSHA256"], "update/rollback proof")
    require_equal(update_rollback, "updateBundleSHA256", update["archiveSHA256"], "update/rollback proof")

    validate_proof(
        uninstall_reinstall,
        "uninstall-reinstall-data-preservation",
        {"preflight", "runtime-data-marker-applied", "uninstall-accepted", "uninstall-completed",
         "uninstall-data-preserved", "offline-reinstall", "reinstall-data-preserved",
         "runtime-settings-restored"},
    )
    require_release(uninstall_reinstall, base, "uninstall/reinstall proof")
    require_equal(uninstall_reinstall, "sealedAcceptanceRunId", base_release["installedAcceptanceRunId"], "uninstall/reinstall proof")
    require_equal(
        uninstall_reinstall,
        "beforeInstalledAcceptanceRunId",
        update_rollback.get("afterRollbackInstalledAcceptanceRunId"),
        "uninstall/reinstall proof",
    )
    if uninstall_reinstall.get("afterInstalledAcceptanceRunId") == uninstall_reinstall.get("beforeInstalledAcceptanceRunId"):
        fail("uninstall/reinstall proof has no new host-local acceptance run")
    require_nonempty(uninstall_reinstall, "runtimeDataVHDXPath", "uninstall/reinstall proof")

    validate_proof(clean_uninstall, "clean-uninstall", {"preflight", "clean-uninstall-accepted", "clean-uninstall-completed"})
    require_release(clean_uninstall, base, "clean uninstall proof")
    require_equal(
        clean_uninstall,
        "installedAcceptanceRunId",
        uninstall_reinstall["afterInstalledAcceptanceRunId"],
        "clean uninstall proof",
    )
    require_nonempty(clean_uninstall, "uninstallOperationId", "clean uninstall proof")

    run_ids = [
        base_release["installedAcceptanceRunId"], clean_host["runId"], reboot["runId"],
        reboot_runtime["runId"], update_rollback["runId"], uninstall_reinstall["runId"],
        clean_uninstall["runId"],
    ]
    if len(set(run_ids)) != len(run_ids):
        fail("Windows lifecycle evidence reuses a runId across different proofs")

    evidence_paths = {
        "sealedBundle": args.sealed_bundle,
        "cleanHostAcceptance": args.clean_host_acceptance,
        "rebootProof": args.reboot_proof,
        "rebootRuntimeAcceptance": args.reboot_runtime_acceptance,
        "updateBundle": args.update_bundle,
        "updateRollbackProof": args.update_rollback_proof,
        "uninstallReinstallProof": args.uninstall_reinstall_proof,
        "cleanUninstallProof": args.clean_uninstall_proof,
    }
    result = {
        "schemaVersion": 1,
        "kind": "windows-runtime-v2-lifecycle-acceptance",
        "state": "passed",
        "platform": "windows-hyperv-amd64",
        "platformVersion": base_release["platformVersion"],
        "runtimeBundleVersion": base_release["runtimeBundleVersion"],
        "updatePlatformVersion": update_release["platformVersion"],
        "updateRuntimeBundleVersion": update_release["runtimeBundleVersion"],
        "sealedAcceptanceRunId": base_release["installedAcceptanceRunId"],
        "cleanHostAcceptanceRunId": clean_host["runId"],
        "completedAt": datetime.now(UTC).isoformat(),
        "evidence": {
            name: {"path": str(path.resolve()), "sha256": sha256(path)}
            for name, path in evidence_paths.items()
        },
    }
    write_json(args.output, result)
    print(f"Windows Runtime v2 lifecycle acceptance passed output={args.output} sha256={sha256(args.output)}")
    return 0


def load_bundle(path: Path) -> dict[str, Any]:
    archive_digest = sha256(path)
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                fail(f"Windows bundle has duplicate ZIP members path={path}")
            files: dict[str, bytes] = {}
            for info in archive.infolist():
                member = PurePosixPath(info.filename)
                if info.is_dir():
                    continue
                if member.is_absolute() or ".." in member.parts or not member.parts or member.parts[0] != ROOT:
                    fail(f"Windows bundle member is unsafe path={path} member={info.filename}")
                files[info.filename] = archive.read(info)
    except (OSError, zipfile.BadZipFile) as error:
        fail(f"Windows bundle read failed path={path}: {error}")
    checksum_name = f"{ROOT}/checksums.sha256"
    if checksum_name not in files:
        fail(f"Windows bundle checksum inventory is missing path={path}")
    expected: dict[str, str] = {}
    try:
        lines = files[checksum_name].decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        fail(f"Windows bundle checksum inventory is invalid UTF-8 path={path}: {error}")
    for line in lines:
        if len(line) < 67 or line[64:66] != "  ":
            fail(f"Windows bundle checksum line is invalid path={path}")
        digest, relative = line[:64], line[66:]
        if not is_sha256(digest) or relative in expected:
            fail(f"Windows bundle checksum entry is invalid path={path} member={relative}")
        expected[relative] = digest
    actual_names = {name.removeprefix(f"{ROOT}/") for name in files if name != checksum_name}
    if set(expected) != actual_names:
        fail(f"Windows bundle checksum inventory differs path={path}")
    for relative, digest in expected.items():
        actual = hashlib.sha256(files[f"{ROOT}/{relative}"]).hexdigest()
        if actual != digest:
            fail(f"Windows bundle member checksum differs path={path} member={relative}")
    release = parse_json_bytes(files.get(f"{ROOT}/release.json"), f"bundle release path={path}")
    proof = parse_json_bytes(files.get(f"{ROOT}/proof/windows-hyperv-acceptance.json"), f"bundle acceptance path={path}")
    if release.get("schemaVersion") != 1 or release.get("state") != "releaseCandidate":
        fail(f"Windows bundle is not a sealed releaseCandidate path={path}")
    require_nonempty(release, "platformVersion", f"bundle release path={path}")
    require_nonempty(release, "runtimeBundleVersion", f"bundle release path={path}")
    require_nonempty(release, "installedAcceptanceRunId", f"bundle release path={path}")
    if proof.get("status") != "passed" or proof.get("runId") != release["installedAcceptanceRunId"]:
        fail(f"Windows bundle sealing proof identity differs path={path}")
    return {
        "path": path,
        "archiveSHA256": archive_digest,
        "release": release,
        "releaseSHA256": hashlib.sha256(files[f"{ROOT}/release.json"]).hexdigest(),
        "proof": proof,
    }


def validate_runtime_acceptance(value: dict[str, Any], bundle: dict[str, Any], label: str) -> None:
    validate_proof(value, None, RUNTIME_STAGES)
    require_release(value, bundle, label)
    release = bundle["release"]
    if value.get("releaseInputs") != release.get("inputs"):
        fail(f"{label} releaseInputs differ from the sealed bundle")
    require_nonempty(value, "hostBootSessionId", label)
    require_nonempty(value, "supportExportOperationId", label)
    if not is_sha256(value.get("supportArtifactSHA256")) or not isinstance(value.get("supportArtifactSizeBytes"), int) or value["supportArtifactSizeBytes"] <= 0:
        fail(f"{label} support artifact evidence is invalid")


def validate_proof(value: dict[str, Any], kind: str | None, stages: set[str]) -> None:
    label = kind or "Runtime acceptance"
    if value.get("schemaVersion") != 1 or value.get("platform") != "windows-hyperv-amd64" or value.get("status") != "passed":
        fail(f"{label} is not a passed Windows Hyper-V proof")
    if kind is not None and value.get("kind") != kind:
        fail(f"{label} kind differs actual={value.get('kind')}")
    require_nonempty(value, "runId", label)
    if value.get("failureStage") is not None or value.get("failureReason") is not None:
        fail(f"{label} contains failure evidence")
    passed = {stage.get("name") for stage in value.get("stages", []) if isinstance(stage, dict) and stage.get("status") == "passed"}
    missing = stages - passed
    if missing:
        fail(f"{label} misses passed stages: {', '.join(sorted(missing))}")


def require_release(value: dict[str, Any], bundle: dict[str, Any], label: str) -> None:
    release = bundle["release"]
    require_equal(value, "platformVersion", release["platformVersion"], label)
    require_equal(value, "runtimeBundleVersion", release["runtimeBundleVersion"], label)
    require_equal(value, "releaseManifestSHA256", bundle["releaseSHA256"], label)


def require_equal(value: dict[str, Any], field: str, expected: Any, label: str) -> None:
    if value.get(field) != expected:
        fail(f"{label} field differs field={field} expected={expected} actual={value.get(field)}")


def require_nonempty(value: dict[str, Any], field: str, label: str) -> None:
    if not isinstance(value.get(field), str) or not value[field]:
        fail(f"{label} field is missing or empty field={field}")


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} read failed path={path}: {error}")
    if not isinstance(value, dict):
        fail(f"{label} is not an object path={path}")
    return value


def parse_json_bytes(data: bytes | None, label: str) -> dict[str, Any]:
    if data is None:
        fail(f"{label} is missing")
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} is invalid: {error}")
    if not isinstance(value, dict):
        fail(f"{label} is not an object")
    return value


def is_sha256(value: Any) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def fail(message: str) -> None:
    raise SystemExit(message)


if __name__ == "__main__":
    raise SystemExit(main())
