"""Compose one explicit Host-installer plus Runtime-Console delivery kit.

The release process owns this delivery boundary.  It binds already-produced
Host-installer bytes to an already-produced Runtime Console C71 receipt and
the exact C53 bootstrap configuration that the packaged Console will read.
It deliberately does not install either artifact, discover a product version,
or convert a kit into C24 clean-host evidence.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractRepository, ContractToolError, load_json
from tooling.product_delivery_release_plan import (
    ProductDeliveryReleasePlanError,
    validate_c23_release_delivery_plan,
)


class OperatorDeliveryKitCompositionError(RuntimeError):
    """One explicit delivery-kit source is absent, malformed, or inconsistent."""


@dataclass(frozen=True)
class OperatorDeliveryKitComposition:
    """Release-process-owned source selection for one C72 delivery kit."""

    release_set_id: str
    release_delivery_plans_document: Path
    release_delivery_plan_id: str
    host_installer_artifact: Path
    runtime_console_artifact: Path
    runtime_console_artifact_receipt: Path
    operator_interface_bootstrap_configuration: Path
    output_directory: Path


_identifier_pattern = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
OPERATOR_INTERFACE_BOOTSTRAP_PATH_BY_PLATFORM = {
    "macos": "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json",
    "windows": r"C:\ProgramData\VitalServerRuntimePlatform\control\runtime-console-bootstrap.json",
    "linux": "/opt/vitalserver-runtime-platform/control/runtime-console-bootstrap.json",
}


def compose_operator_delivery_kit(
    composition: OperatorDeliveryKitComposition,
) -> Mapping[str, Any]:
    """Atomically publish an immutable C72 kit with copied, verified bytes."""

    _validate_composition_paths(composition)
    plan = _load_selected_release_delivery_plan(
        composition.release_delivery_plans_document,
        composition.release_delivery_plan_id,
    )
    host_artifact = _verify_host_installer(composition.host_installer_artifact, plan)
    console_receipt = _read_validated_document(
        composition.runtime_console_artifact_receipt,
        "runtime-console-desktop-artifact-receipt.schema.json",
        "C71 RuntimeConsoleDesktopArtifactReceipt",
    )
    _verify_console_artifact(composition.runtime_console_artifact, console_receipt, plan)
    bootstrap = _read_validated_document(
        composition.operator_interface_bootstrap_configuration,
        "operator-interface-bootstrap-configuration.schema.json",
        "C53 OperatorInterfaceBootstrapConfiguration",
    )
    _verify_bootstrap(bootstrap, composition.operator_interface_bootstrap_configuration, plan)
    manifest = _compose_manifest(composition, plan, host_artifact, console_receipt)
    _validate_document_instance(
        "operator-delivery-kit-manifest.schema.json",
        manifest,
        "C72 OperatorDeliveryKitManifest",
    )
    _publish_kit(composition, manifest)
    manifest_path = composition.output_directory / "operator-delivery-kit-manifest.json"
    return {
        "outputDirectory": str(composition.output_directory),
        "manifestPath": str(manifest_path),
        "manifestSHA256": _sha256_file(manifest_path),
        "hostInstallerArtifactPath": str(
            composition.output_directory / "artifacts" / "host-installer" / host_artifact["fileName"]
        ),
        "runtimeConsoleArtifactPath": str(
            composition.output_directory
            / "artifacts"
            / "runtime-console"
            / str(console_receipt["artifact"]["fileName"])
        ),
    }


def _validate_composition_paths(composition: OperatorDeliveryKitComposition) -> None:
    if not _identifier_pattern.fullmatch(composition.release_set_id):
        raise OperatorDeliveryKitCompositionError("release set id is invalid")
    if not composition.release_delivery_plan_id:
        raise OperatorDeliveryKitCompositionError("release delivery plan id is required")
    for label, path in (
        ("C23 release delivery plans document", composition.release_delivery_plans_document),
        ("Host installer artifact", composition.host_installer_artifact),
        ("C71 Runtime Console artifact", composition.runtime_console_artifact),
        ("C71 Runtime Console artifact receipt", composition.runtime_console_artifact_receipt),
        ("C53 bootstrap configuration", composition.operator_interface_bootstrap_configuration),
    ):
        _require_absolute_regular_file(path, label)
    if not composition.output_directory.is_absolute():
        raise OperatorDeliveryKitCompositionError("delivery-kit output directory must be absolute")
    if composition.output_directory.exists() or composition.output_directory.is_symlink():
        raise OperatorDeliveryKitCompositionError(
            "delivery-kit output directory already exists: " + str(composition.output_directory)
        )


def _load_selected_release_delivery_plan(path: Path, plan_id: str) -> Mapping[str, Any]:
    try:
        document = load_json(path)
    except ContractToolError as error:
        raise OperatorDeliveryKitCompositionError(
            "C23 release delivery plans document cannot be read: " + str(error)
        ) from error
    plans = document.get("plans")
    if document.get("schemaVersion") != "v1" or not isinstance(plans, list):
        raise OperatorDeliveryKitCompositionError(
            "C23 release delivery plans document requires schemaVersion v1 and plans"
        )
    selected = [plan for plan in plans if isinstance(plan, dict) and plan.get("id") == plan_id]
    if len(selected) != 1:
        raise OperatorDeliveryKitCompositionError(
            "C23 release delivery plan must occur exactly once: " + plan_id
        )
    try:
        validate_c23_release_delivery_plan(selected[0])
    except ProductDeliveryReleasePlanError as error:
        raise OperatorDeliveryKitCompositionError(
            "selected C23 release delivery plan is invalid: " + str(error)
        ) from error
    return selected[0]


def _verify_host_installer(path: Path, plan: Mapping[str, Any]) -> Mapping[str, Any]:
    artifact = _required_object(plan, "intendedInstallerArtifact", "C23 release delivery plan")
    expected_name = _required_string(artifact, "expectedName", "C23 intended installer artifact")
    if path.name != expected_name:
        raise OperatorDeliveryKitCompositionError(
            "Host installer artifact file name does not match C23: " + path.name
        )
    return {
        "kind": _required_string(artifact, "kind", "C23 intended installer artifact"),
        "fileName": path.name,
        "sha256": _sha256_file(path),
        "sizeBytes": path.stat().st_size,
    }


def _verify_console_artifact(
    path: Path, receipt: Mapping[str, Any], plan: Mapping[str, Any]
) -> None:
    artifact = _required_object(receipt, "artifact", "C71 Runtime Console artifact receipt")
    platform = _required_string(plan, "platform", "C23 release delivery plan")
    if artifact.get("platform") != platform:
        raise OperatorDeliveryKitCompositionError(
            "C71 Runtime Console artifact platform does not match C23"
        )
    if path.name != artifact.get("fileName"):
        raise OperatorDeliveryKitCompositionError(
            "Runtime Console artifact file name does not match C71 receipt"
        )
    if _sha256_file(path) != artifact.get("sha256"):
        raise OperatorDeliveryKitCompositionError(
            "Runtime Console artifact SHA-256 does not match C71 receipt"
        )
    if path.stat().st_size != artifact.get("sizeBytes"):
        raise OperatorDeliveryKitCompositionError(
            "Runtime Console artifact size does not match C71 receipt"
        )
    local_control = _required_object(
        receipt, "localControlBootstrapContract", "C71 Runtime Console artifact receipt"
    )
    if local_control.get("contractId") != "C53" or local_control.get("schemaVersion") != "v1":
        raise OperatorDeliveryKitCompositionError(
            "C71 Runtime Console artifact must require C53 schemaVersion v1"
        )


def _verify_bootstrap(
    bootstrap: Mapping[str, Any], path: Path, plan: Mapping[str, Any]
) -> None:
    platform = _required_string(plan, "platform", "C23 release delivery plan")
    expected_path = OPERATOR_INTERFACE_BOOTSTRAP_PATH_BY_PLATFORM[platform]
    if bootstrap.get("schemaVersion") != "v1":
        raise OperatorDeliveryKitCompositionError("C53 bootstrap schemaVersion must be v1")
    if bootstrap.get("bootstrapConfigurationPath") != expected_path:
        raise OperatorDeliveryKitCompositionError(
            "C53 bootstrap path does not match the packaged Runtime Console path for " + platform
        )
    if path.stat().st_size > 16 * 1024:
        raise OperatorDeliveryKitCompositionError("C53 bootstrap configuration exceeds 16 KiB")


def _compose_manifest(
    composition: OperatorDeliveryKitComposition,
    plan: Mapping[str, Any],
    host_artifact: Mapping[str, Any],
    console_receipt: Mapping[str, Any],
) -> Mapping[str, Any]:
    return {
        "schemaVersion": "v1",
        "releaseSetId": composition.release_set_id,
        "releaseDeliveryPlan": {
            "planId": _required_string(plan, "id", "C23 release delivery plan"),
            "productVersion": _required_string(plan, "productVersion", "C23 release delivery plan"),
            "platform": _required_string(plan, "platform", "C23 release delivery plan"),
            "providerKind": _required_string(plan, "providerKind", "C23 release delivery plan"),
        },
        "hostInstallerArtifact": dict(host_artifact),
        "runtimeConsoleArtifactReceipt": dict(console_receipt),
        "operatorInterfaceBootstrap": {
            "contractId": "C53",
            "schemaVersion": "v1",
            "sha256": _sha256_file(composition.operator_interface_bootstrap_configuration),
        },
        "installationOrder": ["host-installer", "runtime-console"],
    }


def _publish_kit(
    composition: OperatorDeliveryKitComposition, manifest: Mapping[str, Any]
) -> None:
    composition.output_directory.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(
            prefix="." + composition.output_directory.name + ".compose-",
            dir=composition.output_directory.parent,
        )
    )
    try:
        host_target = temporary / "artifacts" / "host-installer" / composition.host_installer_artifact.name
        console_target = temporary / "artifacts" / "runtime-console" / composition.runtime_console_artifact.name
        host_target.parent.mkdir(parents=True, exist_ok=False)
        console_target.parent.mkdir(parents=True, exist_ok=False)
        _copy_regular_file(composition.host_installer_artifact, host_target)
        _copy_regular_file(composition.runtime_console_artifact, console_target)
        manifest_path = temporary / "operator-delivery-kit-manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, composition.output_directory)
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def _read_validated_document(path: Path, schema_name: str, label: str) -> Mapping[str, Any]:
    try:
        document = load_json(path)
    except ContractToolError as error:
        raise OperatorDeliveryKitCompositionError(label + " cannot be read: " + str(error)) from error
    _validate_document_instance(schema_name, document, label)
    return document


def _validate_document_instance(schema_name: str, document: Mapping[str, Any], label: str) -> None:
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        findings = repository.validate_instance(schema_name, document)
    except ContractToolError as error:
        raise OperatorDeliveryKitCompositionError(label + " contract source is unavailable: " + str(error)) from error
    if findings:
        raise OperatorDeliveryKitCompositionError(label + " is invalid: " + "; ".join(findings))


def _copy_regular_file(source: Path, target: Path) -> None:
    _require_absolute_regular_file(source, "delivery-kit artifact")
    shutil.copyfile(source, target)
    target.chmod(0o644)


def _require_absolute_regular_file(path: Path, label: str) -> None:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise OperatorDeliveryKitCompositionError(label + " must be one absolute regular non-symlink file: " + str(path))
    if path.stat().st_size < 1:
        raise OperatorDeliveryKitCompositionError(label + " must not be empty: " + str(path))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _required_object(document: Mapping[str, Any], key: str, label: str) -> Mapping[str, Any]:
    value = document.get(key)
    if not isinstance(value, dict):
        raise OperatorDeliveryKitCompositionError(label + " requires object " + key)
    return value


def _required_string(document: Mapping[str, Any], key: str, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise OperatorDeliveryKitCompositionError(label + " requires non-empty " + key)
    return value


def _parse_arguments(arguments: Sequence[str] | None = None) -> OperatorDeliveryKitComposition:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-set-id", required=True)
    parser.add_argument("--release-delivery-plans-document", required=True, type=Path)
    parser.add_argument("--release-delivery-plan-id", required=True)
    parser.add_argument("--host-installer-artifact", required=True, type=Path)
    parser.add_argument("--runtime-console-artifact", required=True, type=Path)
    parser.add_argument("--runtime-console-artifact-receipt", required=True, type=Path)
    parser.add_argument("--operator-interface-bootstrap-configuration", required=True, type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    parsed = parser.parse_args(arguments)
    return OperatorDeliveryKitComposition(
        release_set_id=parsed.release_set_id,
        release_delivery_plans_document=parsed.release_delivery_plans_document,
        release_delivery_plan_id=parsed.release_delivery_plan_id,
        host_installer_artifact=parsed.host_installer_artifact,
        runtime_console_artifact=parsed.runtime_console_artifact,
        runtime_console_artifact_receipt=parsed.runtime_console_artifact_receipt,
        operator_interface_bootstrap_configuration=parsed.operator_interface_bootstrap_configuration,
        output_directory=parsed.output_directory,
    )


def main(arguments: Sequence[str] | None = None) -> int:
    try:
        result = compose_operator_delivery_kit(_parse_arguments(arguments))
    except OperatorDeliveryKitCompositionError as error:
        print("operator delivery-kit composition failed: " + str(error), flush=True)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
