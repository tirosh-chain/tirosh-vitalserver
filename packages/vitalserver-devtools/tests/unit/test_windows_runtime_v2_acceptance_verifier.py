from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[4]
VERIFIER = ROOT / "scripts/verify_windows_runtime_v2_acceptance.py"
RUNTIME_STAGES = {
    "preflight", "runtime-provider-running", "platform-contract", "runtime-capabilities",
    "runtime-services", "runtime-stack", "runtime-settings", "redis-relay-settings",
    "runtime-events", "product-pwa", "platform-support-export", "runtime-provider-stop",
    "runtime-provider-start", "runtime-after-provider-restart",
}


def test_windows_lifecycle_verifier_accepts_one_explicit_identity_chain(tmp_path: Path) -> None:
    paths = write_evidence_chain(tmp_path)
    output = tmp_path / "result.json"
    result = run_verifier(paths, output)

    assert result.returncode == 0, result.stderr
    document = json.loads(output.read_text())
    assert document["state"] == "passed"
    assert document["kind"] == "windows-runtime-v2-lifecycle-acceptance"
    assert document["cleanHostAcceptanceRunId"] == "clean-host-run"
    assert set(document["evidence"]) == {
        "sealedBundle", "cleanHostAcceptance", "rebootProof", "rebootRuntimeAcceptance",
        "updateBundle", "updateRollbackProof", "uninstallReinstallProof", "cleanUninstallProof",
    }


def test_windows_lifecycle_verifier_rejects_mixed_clean_uninstall_identity(tmp_path: Path) -> None:
    paths = write_evidence_chain(tmp_path)
    clean = json.loads(paths["clean_uninstall"].read_text())
    clean["installedAcceptanceRunId"] = "another-host-install"
    paths["clean_uninstall"].write_text(json.dumps(clean), encoding="utf-8")

    result = run_verifier(paths, tmp_path / "result.json")

    assert result.returncode != 0
    assert "clean uninstall proof field differs field=installedAcceptanceRunId" in result.stderr


def write_evidence_chain(root: Path) -> dict[str, Path]:
    base_bundle, base_release, base_release_sha = write_bundle(root / "base.zip", "2.0.0", "2.3.4", "seal-run")
    update_bundle, update_release, _ = write_bundle(root / "update.zip", "2.0.1", "2.3.5", "update-seal-run")
    clean_host = runtime_acceptance("clean-host-run", base_release, base_release_sha, "boot-1")
    reboot_runtime = runtime_acceptance("reboot-runtime-run", base_release, base_release_sha, "boot-2")
    reboot = proof(
        "reboot-run", "reboot", {"preflight", "boot-session-changed", "installed-runtime-acceptance"},
        platformVersion="2.0.0", runtimeBundleVersion="2.3.4", releaseManifestSHA256=base_release_sha,
        installedAcceptanceRunId="clean-host-run", runtimeAcceptanceRunId="reboot-runtime-run",
        installedBootSessionId="boot-1", currentBootSessionId="boot-2",
    )
    update_rollback = proof(
        "update-rollback-run", "update-rollback-data-preservation",
        {"preflight", "runtime-data-marker-applied", "update-accepted", "update-completed",
         "update-data-preserved", "rollback-accepted", "rollback-completed",
         "rollback-data-preserved", "runtime-settings-restored"},
        originalPlatformVersion="2.0.0", originalRuntimeBundleVersion="2.3.4",
        updatePlatformVersion="2.0.1", updateRuntimeBundleVersion="2.3.5",
        beforeInstalledAcceptanceRunId="clean-host-run", afterRollbackInstalledAcceptanceRunId="clean-host-run",
        originalReleaseManifestSHA256=base_release_sha, updateBundleSHA256=sha256(update_bundle),
    )
    uninstall_reinstall = proof(
        "uninstall-reinstall-run", "uninstall-reinstall-data-preservation",
        {"preflight", "runtime-data-marker-applied", "uninstall-accepted", "uninstall-completed",
         "uninstall-data-preserved", "offline-reinstall", "reinstall-data-preserved", "runtime-settings-restored"},
        platformVersion="2.0.0", runtimeBundleVersion="2.3.4", releaseManifestSHA256=base_release_sha,
        sealedAcceptanceRunId="seal-run", beforeInstalledAcceptanceRunId="clean-host-run",
        afterInstalledAcceptanceRunId="reinstall-local-run", runtimeDataVHDXPath="C:\\ProgramData\\VitalServer\\vm\\data.vhdx",
    )
    clean_uninstall = proof(
        "clean-uninstall-run", "clean-uninstall",
        {"preflight", "clean-uninstall-accepted", "clean-uninstall-completed"},
        platformVersion="2.0.0", runtimeBundleVersion="2.3.4", releaseManifestSHA256=base_release_sha,
        installedAcceptanceRunId="reinstall-local-run", uninstallOperationId="uninstall-operation",
    )
    paths = {
        "sealed_bundle": base_bundle,
        "clean_host": root / "clean-host.json",
        "reboot": root / "reboot.json",
        "reboot_runtime": root / "reboot-runtime.json",
        "update_bundle": update_bundle,
        "update_rollback": root / "update-rollback.json",
        "uninstall_reinstall": root / "uninstall-reinstall.json",
        "clean_uninstall": root / "clean-uninstall.json",
    }
    for key, document in (
        ("clean_host", clean_host), ("reboot", reboot), ("reboot_runtime", reboot_runtime),
        ("update_rollback", update_rollback), ("uninstall_reinstall", uninstall_reinstall),
        ("clean_uninstall", clean_uninstall),
    ):
        paths[key].write_text(json.dumps(document), encoding="utf-8")
    assert update_release["platformVersion"] == "2.0.1"
    return paths


def write_bundle(path: Path, platform_version: str, runtime_version: str, run_id: str) -> tuple[Path, dict, str]:
    release = {
        "schemaVersion": 1, "state": "releaseCandidate", "platformVersion": platform_version,
        "runtimeBundleVersion": runtime_version, "installedAcceptanceRunId": run_id,
        "inputs": {"artifact": f"{platform_version}-{runtime_version}"},
    }
    proof_document = {"schemaVersion": 1, "status": "passed", "runId": run_id}
    release_bytes = json.dumps(release, sort_keys=True).encode()
    proof_bytes = json.dumps(proof_document, sort_keys=True).encode()
    members = {
        "release.json": release_bytes,
        "proof/windows-hyperv-acceptance.json": proof_bytes,
    }
    checksums = "".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n" for name, data in sorted(members.items())).encode()
    with zipfile.ZipFile(path, "w") as archive:
        for name, data in members.items():
            archive.writestr(f"VitalServer-Windows/{name}", data)
        archive.writestr("VitalServer-Windows/checksums.sha256", checksums)
    return path, release, hashlib.sha256(release_bytes).hexdigest()


def runtime_acceptance(run_id: str, release: dict, release_sha: str, boot: str) -> dict:
    return proof(
        run_id, None, RUNTIME_STAGES,
        platformVersion=release["platformVersion"], runtimeBundleVersion=release["runtimeBundleVersion"],
        releaseManifestSHA256=release_sha, releaseInputs=release["inputs"], hostBootSessionId=boot,
        supportExportOperationId=f"support-{run_id}", supportArtifactSHA256="a" * 64,
        supportArtifactSizeBytes=42,
    )


def proof(run_id: str, kind: str | None, stages: set[str], **fields: object) -> dict:
    value = {
        "schemaVersion": 1, "runId": run_id, "platform": "windows-hyperv-amd64",
        "status": "passed", "failureStage": None, "failureReason": None,
        "stages": [{"name": name, "status": "passed"} for name in sorted(stages)],
        **fields,
    }
    if kind is not None:
        value["kind"] = kind
    return value


def run_verifier(paths: dict[str, Path], output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VERIFIER),
         "--sealed-bundle", str(paths["sealed_bundle"]),
         "--clean-host-acceptance", str(paths["clean_host"]),
         "--reboot-proof", str(paths["reboot"]),
         "--reboot-runtime-acceptance", str(paths["reboot_runtime"]),
         "--update-bundle", str(paths["update_bundle"]),
         "--update-rollback-proof", str(paths["update_rollback"]),
         "--uninstall-reinstall-proof", str(paths["uninstall_reinstall"]),
         "--clean-uninstall-proof", str(paths["clean_uninstall"]),
         "--output", str(output)],
        text=True, capture_output=True,
    )


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
