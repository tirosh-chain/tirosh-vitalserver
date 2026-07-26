"""Verify one already-published C72 operator delivery kit without installing it.

The release process owns this read-only integrity boundary. It checks the C72
manifest and the two copied installer artifacts before an operator invokes an
OS installer. An optional explicitly supplied C53 bootstrap file can be checked
against the C72 identity after Host installation. This tool never discovers a
bootstrap path, starts a service, or turns byte verification into installation
or C24 clean-Host evidence.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractRepository, ContractToolError, load_json
from tooling.operator_delivery_kit_composer import OPERATOR_INTERFACE_BOOTSTRAP_PATH_BY_PLATFORM


class OperatorDeliveryKitVerificationError(RuntimeError):
    """A C72 kit, copied artifact, or explicitly supplied C53 file is invalid."""


@dataclass(frozen=True)
class OperatorDeliveryKitVerification:
    """One operator-selected C72 directory and optional Host-installed C53 file."""

    delivery_kit_directory: Path
    operator_interface_bootstrap_configuration: Path | None = None


_MANIFEST_NAME = "operator-delivery-kit-manifest.json"
_EXPECTED_DIRECTORIES = {
    Path("artifacts"),
    Path("artifacts") / "host-installer",
    Path("artifacts") / "runtime-console",
}


def verify_operator_delivery_kit(
    verification: OperatorDeliveryKitVerification,
) -> Mapping[str, Any]:
    """Return explicit read-only integrity facts for one immutable C72 kit."""

    _require_absolute_directory(verification.delivery_kit_directory, "C72 delivery-kit directory")
    manifest_path = verification.delivery_kit_directory / _MANIFEST_NAME
    _require_regular_file_under_directory(verification.delivery_kit_directory, Path(_MANIFEST_NAME), "C72 manifest")
    manifest = _read_validated_document(manifest_path, "operator-delivery-kit-manifest.schema.json", "C72 OperatorDeliveryKitManifest")
    host_artifact = _required_object(manifest, "hostInstallerArtifact", "C72 manifest")
    console_receipt = _required_object(manifest, "runtimeConsoleArtifactReceipt", "C72 manifest")
    console_artifact = _required_object(console_receipt, "artifact", "C71 Runtime Console artifact receipt")
    host_path = _artifact_path(verification.delivery_kit_directory, "host-installer", host_artifact, "Host installer artifact")
    console_path = _artifact_path(verification.delivery_kit_directory, "runtime-console", console_artifact, "Runtime Console artifact")
    _verify_artifact_identity(host_path, host_artifact, "Host installer artifact")
    _verify_artifact_identity(console_path, console_artifact, "Runtime Console artifact")
    _reject_unexpected_kit_entries(
        verification.delivery_kit_directory,
        {Path(_MANIFEST_NAME), host_path.relative_to(verification.delivery_kit_directory), console_path.relative_to(verification.delivery_kit_directory)},
    )
    bootstrap_result = _verify_optional_bootstrap(verification, manifest)
    release_plan = _required_object(manifest, "releaseDeliveryPlan", "C72 manifest")
    return {
        "kitIntegrityState": "verified",
        "deliveryKitDirectory": str(verification.delivery_kit_directory),
        "manifestPath": str(manifest_path),
        "manifestSHA256": _sha256_file(manifest_path),
        "releaseSetId": _required_string(manifest, "releaseSetId", "C72 manifest"),
        "releaseDeliveryPlan": {
            "planId": _required_string(release_plan, "planId", "C72 release delivery plan"),
            "productVersion": _required_string(release_plan, "productVersion", "C72 release delivery plan"),
            "platform": _required_string(release_plan, "platform", "C72 release delivery plan"),
            "providerKind": _required_string(release_plan, "providerKind", "C72 release delivery plan"),
        },
        "verifiedArtifacts": {
            "hostInstaller": _artifact_result(host_path, host_artifact),
            "runtimeConsole": _artifact_result(console_path, console_artifact),
        },
        "operatorInterfaceBootstrapVerification": bootstrap_result,
    }


def _require_absolute_directory(path: Path, label: str) -> None:
    if not path.is_absolute() or not path.is_dir() or path.is_symlink():
        raise OperatorDeliveryKitVerificationError(label + " must be one existing absolute non-symlink directory: " + str(path))


def _artifact_path(directory: Path, category: str, artifact: Mapping[str, Any], label: str) -> Path:
    file_name = _safe_file_name(_required_string(artifact, "fileName", label), label)
    relative = Path("artifacts") / category / file_name
    _require_regular_file_under_directory(directory, relative, label)
    return directory / relative


def _verify_artifact_identity(path: Path, artifact: Mapping[str, Any], label: str) -> None:
    expected_size = artifact.get("sizeBytes")
    expected_sha256 = artifact.get("sha256")
    if not isinstance(expected_size, int) or expected_size < 1:
        raise OperatorDeliveryKitVerificationError(label + " has invalid C72 size identity")
    if not isinstance(expected_sha256, str) or len(expected_sha256) != 64:
        raise OperatorDeliveryKitVerificationError(label + " has invalid C72 SHA-256 identity")
    if path.stat().st_size != expected_size:
        raise OperatorDeliveryKitVerificationError(label + " size does not match C72 manifest")
    if _sha256_file(path) != expected_sha256:
        raise OperatorDeliveryKitVerificationError(label + " SHA-256 does not match C72 manifest")


def _reject_unexpected_kit_entries(directory: Path, expected_files: set[Path]) -> None:
    observed_files: set[Path] = set()
    for path in directory.rglob("*"):
        relative = path.relative_to(directory)
        if path.is_symlink():
            raise OperatorDeliveryKitVerificationError("C72 delivery kit contains a symbolic link: " + str(relative))
        if path.is_dir():
            if relative not in _EXPECTED_DIRECTORIES:
                raise OperatorDeliveryKitVerificationError("C72 delivery kit contains an unexpected directory: " + str(relative))
            continue
        if not path.is_file():
            raise OperatorDeliveryKitVerificationError("C72 delivery kit contains a non-regular entry: " + str(relative))
        observed_files.add(relative)
    if observed_files != expected_files:
        raise OperatorDeliveryKitVerificationError(
            "C72 delivery kit files do not exactly match its manifest: expected "
            + ", ".join(sorted(str(path) for path in expected_files))
            + "; observed "
            + ", ".join(sorted(str(path) for path in observed_files))
        )


def _verify_optional_bootstrap(verification: OperatorDeliveryKitVerification, manifest: Mapping[str, Any]) -> Mapping[str, Any]:
    path = verification.operator_interface_bootstrap_configuration
    if path is None:
        return {"state": "not-provided"}
    _require_absolute_regular_file(path, "C53 OperatorInterfaceBootstrapConfiguration")
    bootstrap = _read_validated_document(path, "operator-interface-bootstrap-configuration.schema.json", "C53 OperatorInterfaceBootstrapConfiguration")
    release_plan = _required_object(manifest, "releaseDeliveryPlan", "C72 manifest")
    platform = _required_string(release_plan, "platform", "C72 release delivery plan")
    if bootstrap.get("bootstrapConfigurationPath") != OPERATOR_INTERFACE_BOOTSTRAP_PATH_BY_PLATFORM[platform]:
        raise OperatorDeliveryKitVerificationError("C53 bootstrap path does not match packaged Runtime Console path for " + platform)
    identity = _required_object(manifest, "operatorInterfaceBootstrap", "C72 manifest")
    observed_sha256 = _sha256_file(path)
    if observed_sha256 != _required_string(identity, "sha256", "C72 operator interface bootstrap"):
        raise OperatorDeliveryKitVerificationError("C53 bootstrap SHA-256 does not match C72 manifest")
    return {"state": "verified", "path": str(path), "sha256": observed_sha256}


def _read_validated_document(path: Path, schema_name: str, label: str) -> Mapping[str, Any]:
    try:
        document = load_json(path)
    except ContractToolError as error:
        raise OperatorDeliveryKitVerificationError(label + " cannot be read: " + str(error)) from error
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        findings = repository.validate_instance(schema_name, document)
    except ContractToolError as error:
        raise OperatorDeliveryKitVerificationError(label + " contract source is unavailable: " + str(error)) from error
    if findings:
        raise OperatorDeliveryKitVerificationError(label + " is invalid: " + "; ".join(findings))
    return document


def _require_regular_file_under_directory(directory: Path, relative: Path, label: str) -> None:
    if relative.is_absolute() or ".." in relative.parts:
        raise OperatorDeliveryKitVerificationError(label + " path is not a safe C72 relative path")
    current = directory
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise OperatorDeliveryKitVerificationError(label + " must not be a symbolic link: " + str(current))
    if not current.is_file():
        raise OperatorDeliveryKitVerificationError(label + " is missing or not a regular file: " + str(current))


def _require_absolute_regular_file(path: Path, label: str) -> None:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise OperatorDeliveryKitVerificationError(label + " must be one absolute regular non-symlink file: " + str(path))


def _safe_file_name(value: str, label: str) -> str:
    candidate = Path(value)
    if value in {"", ".", ".."} or candidate.name != value or any(part == ".." for part in candidate.parts):
        raise OperatorDeliveryKitVerificationError(label + " file name is not safe")
    return value


def _artifact_result(path: Path, artifact: Mapping[str, Any]) -> Mapping[str, Any]:
    return {
        "path": str(path),
        "fileName": _required_string(artifact, "fileName", "C72 artifact"),
        "sha256": _required_string(artifact, "sha256", "C72 artifact"),
        "sizeBytes": artifact["sizeBytes"],
    }


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _required_object(document: Mapping[str, Any], key: str, label: str) -> Mapping[str, Any]:
    value = document.get(key)
    if not isinstance(value, dict):
        raise OperatorDeliveryKitVerificationError(label + " requires object " + key)
    return value


def _required_string(document: Mapping[str, Any], key: str, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise OperatorDeliveryKitVerificationError(label + " requires non-empty " + key)
    return value


def _parse_arguments(arguments: Sequence[str] | None = None) -> OperatorDeliveryKitVerification:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--delivery-kit-directory", required=True, type=Path)
    parser.add_argument("--operator-interface-bootstrap-configuration", type=Path)
    parsed = parser.parse_args(arguments)
    return OperatorDeliveryKitVerification(parsed.delivery_kit_directory, parsed.operator_interface_bootstrap_configuration)


def main(arguments: Sequence[str] | None = None) -> int:
    try:
        result = verify_operator_delivery_kit(_parse_arguments(arguments))
    except OperatorDeliveryKitVerificationError as error:
        print("operator delivery-kit verification failed: " + str(error), flush=True)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
