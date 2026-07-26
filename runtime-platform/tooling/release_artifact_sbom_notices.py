#!/usr/bin/env python3
"""Publish C24-ready, installer-identity-bound SBOM and notice evidence.

This is a release-process tool.  It does not inspect a running Host, install
anything, or edit the reviewed C24 proof set.  A matching clean-Host runner
selects the C23 installer, declares precisely which policy components its
release composition contains, and receives one immutable SPDX, notices file,
evidence document, and C24 proof fragment for review.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractToolError, load_json
from tooling.product_delivery_release_plan import (
    ProductDeliveryReleasePlanError,
    validate_c23_release_delivery_plan,
)


class ReleaseArtifactSBOMAndNoticesError(RuntimeError):
    """The release process cannot make an explicit artifact evidence claim."""


@dataclass(frozen=True)
class ReleaseArtifactSBOMAndNoticesComposition:
    """All release-owned facts required for one C24 SBOM/notices fragment."""

    release_delivery_plans_document: Path
    release_delivery_plan_id: str
    installer_artifact: Path
    component_policy: Path
    component_ids: tuple[str, ...]
    output_directory: Path
    runner_id: str
    recorded_at: str


_RUNNER_KIND_BY_PLATFORM = {
    "macos": "macos-clean-host",
    "windows": "windows-clean-host",
    "linux": "linux-clean-host",
}
_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
_RFC3339_UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def compose_release_artifact_sbom_and_notices(
    composition: ReleaseArtifactSBOMAndNoticesComposition,
) -> Mapping[str, Any]:
    """Create one immutable SBOM/notices evidence directory and C24 fragment."""

    _validate_paths_and_identity(composition)
    plan = _load_selected_plan(
        composition.release_delivery_plans_document,
        composition.release_delivery_plan_id,
    )
    installer = _observe_installer_artifact(
        composition.installer_artifact, plan, composition.recorded_at
    )
    components = _load_selected_components(
        composition.component_policy, composition.component_ids
    )
    sbom = _build_spdx(plan, installer, components, composition.recorded_at)
    notices = _build_notices(plan, installer, components)
    c24_proof = _publish(
        composition.output_directory, sbom, notices, plan, installer, composition
    )
    sbom_path = composition.output_directory / "release-artifact.spdx.json"
    notices_path = composition.output_directory / "THIRD_PARTY_NOTICES.md"
    evidence_path = composition.output_directory / "sbom-and-notices-evidence.json"
    c24_proof_path = composition.output_directory / "release-delivery-proof-fragment.json"
    evidence_sha256 = _sha256_file(evidence_path)
    return {
        "sbomPath": str(sbom_path),
        "sbomSHA256": _sha256_file(sbom_path),
        "noticesPath": str(notices_path),
        "noticesSHA256": _sha256_file(notices_path),
        "evidencePath": str(evidence_path),
        "evidenceSHA256": evidence_sha256,
        "c24ProofPath": str(c24_proof_path),
        "c24Proof": c24_proof,
    }


def _validate_paths_and_identity(
    composition: ReleaseArtifactSBOMAndNoticesComposition,
) -> None:
    if not _IDENTIFIER.fullmatch(composition.release_delivery_plan_id):
        raise ReleaseArtifactSBOMAndNoticesError("release delivery plan id is invalid")
    if not composition.runner_id or len(composition.runner_id) > 255:
        raise ReleaseArtifactSBOMAndNoticesError("clean-Host runner id is required")
    if not _RFC3339_UTC.fullmatch(composition.recorded_at):
        raise ReleaseArtifactSBOMAndNoticesError("recorded at must be an RFC3339 UTC timestamp")
    try:
        datetime.fromisoformat(composition.recorded_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ReleaseArtifactSBOMAndNoticesError("recorded at is not a valid timestamp") from error
    for label, path in (
        ("C23 release delivery plans document", composition.release_delivery_plans_document),
        ("installer artifact", composition.installer_artifact),
        ("SBOM component policy", composition.component_policy),
    ):
        if not path.is_absolute() or not path.is_file() or path.is_symlink():
            raise ReleaseArtifactSBOMAndNoticesError(
                label + " must be one absolute regular non-symlink file: " + str(path)
            )
    if composition.installer_artifact.stat().st_size < 1:
        raise ReleaseArtifactSBOMAndNoticesError("installer artifact must not be empty")
    if not composition.output_directory.is_absolute():
        raise ReleaseArtifactSBOMAndNoticesError("output directory must be absolute")
    if composition.output_directory.exists() or composition.output_directory.is_symlink():
        raise ReleaseArtifactSBOMAndNoticesError(
            "output directory already exists: " + str(composition.output_directory)
        )
    if not composition.component_ids:
        raise ReleaseArtifactSBOMAndNoticesError("component selection is required")
    if len(set(composition.component_ids)) != len(composition.component_ids):
        raise ReleaseArtifactSBOMAndNoticesError(
            "component selection must not contain duplicates"
        )


def _load_selected_plan(path: Path, plan_id: str) -> Mapping[str, Any]:
    try:
        document = load_json(path)
    except ContractToolError as error:
        raise ReleaseArtifactSBOMAndNoticesError(
            "C23 release delivery plans cannot be read: " + str(error)
        ) from error
    plans = document.get("plans")
    if document.get("schemaVersion") != "v1" or not isinstance(plans, list):
        raise ReleaseArtifactSBOMAndNoticesError(
            "C23 release delivery plans require schemaVersion v1 and plans"
        )
    selected = [plan for plan in plans if isinstance(plan, dict) and plan.get("id") == plan_id]
    if len(selected) != 1:
        raise ReleaseArtifactSBOMAndNoticesError(
            "C23 release delivery plan must occur exactly once: " + plan_id
        )
    try:
        validate_c23_release_delivery_plan(selected[0])
    except ProductDeliveryReleasePlanError as error:
        raise ReleaseArtifactSBOMAndNoticesError(
            "selected C23 release delivery plan is invalid: " + str(error)
        ) from error
    return selected[0]


def _observe_installer_artifact(
    path: Path, plan: Mapping[str, Any], observed_at: str
) -> Mapping[str, str]:
    intended = _required_object(plan, "intendedInstallerArtifact", "C23 release plan")
    expected_name = _required_string(intended, "expectedName", "C23 intended installer")
    if path.name != expected_name:
        raise ReleaseArtifactSBOMAndNoticesError(
            "installer artifact file name does not match C23: " + path.name
        )
    return {
        "kind": _required_string(intended, "kind", "C23 intended installer"),
        "fileName": path.name,
        "productVersion": _required_string(plan, "productVersion", "C23 release plan"),
        "sha256": _sha256_file(path),
        "observedAt": observed_at,
    }


def _load_selected_components(path: Path, component_ids: tuple[str, ...]) -> tuple[Mapping[str, str], ...]:
    try:
        policy = load_json(path)
    except ContractToolError as error:
        raise ReleaseArtifactSBOMAndNoticesError(
            "SBOM component policy cannot be read: " + str(error)
        ) from error
    components = policy.get("components")
    allowlist = policy.get("licenseAllowlist")
    if policy.get("schemaVersion") != "v1" or not isinstance(components, list) or not isinstance(allowlist, list):
        raise ReleaseArtifactSBOMAndNoticesError(
            "SBOM component policy requires schemaVersion v1, components, and licenseAllowlist"
        )
    by_id: dict[str, Mapping[str, str]] = {}
    for component in components:
        if not isinstance(component, dict):
            raise ReleaseArtifactSBOMAndNoticesError("SBOM policy component must be an object")
        required = {
            key: _required_string(component, key, "SBOM policy component")
            for key in ("id", "name", "version", "source", "license", "noticeStatus")
        }
        if required["id"] in by_id:
            raise ReleaseArtifactSBOMAndNoticesError(
                "SBOM policy declares duplicate component: " + required["id"]
            )
        if required["license"] not in allowlist:
            raise ReleaseArtifactSBOMAndNoticesError(
                "SBOM component license is not allowlisted: " + required["id"]
            )
        by_id[required["id"]] = required
    selected: list[Mapping[str, str]] = []
    for component_id in component_ids:
        component = by_id.get(component_id)
        if component is None:
            raise ReleaseArtifactSBOMAndNoticesError(
                "selected SBOM component is not declared by policy: " + component_id
            )
        selected.append(component)
    return tuple(selected)


def _build_spdx(
    plan: Mapping[str, Any],
    installer: Mapping[str, str],
    components: tuple[Mapping[str, str], ...],
    recorded_at: str,
) -> Mapping[str, Any]:
    installer_id = "SPDXRef-InstallerArtifact"
    packages: list[Mapping[str, Any]] = [
        {
            "SPDXID": installer_id,
            "name": installer["fileName"],
            "versionInfo": installer["productVersion"],
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": False,
            "packageFileName": installer["fileName"],
            "checksums": [{"algorithm": "SHA256", "checksumValue": installer["sha256"]}],
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
            "supplier": "Organization: Tirosh",
            "primaryPackagePurpose": "APPLICATION",
        }
    ]
    relationships: list[Mapping[str, str]] = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": installer_id,
        }
    ]
    for component in components:
        component_ref = "SPDXRef-" + component["id"]
        packages.append(
            {
                "SPDXID": component_ref,
                "name": component["name"],
                "versionInfo": component["version"],
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False,
                "licenseConcluded": component["license"],
                "licenseDeclared": component["license"],
                "copyrightText": "NOASSERTION",
                "supplier": "NOASSERTION",
                "sourceInfo": "release composition selected policy component; source="
                + component["source"]
                + "; noticeStatus="
                + component["noticeStatus"],
            }
        )
        relationships.append(
            {
                "spdxElementId": installer_id,
                "relationshipType": "CONTAINS",
                "relatedSpdxElement": component_ref,
            }
        )
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "VitalServer Runtime Platform " + plan["platform"] + " release artifact",
        "documentNamespace": "https://tirosh.github.io/vitalserver/runtime-platform/release-artifact/"
        + installer["sha256"],
        "creationInfo": {
            "creators": ["Tool: runtime-platform/release-artifact-sbom-notices"],
            "created": recorded_at,
        },
        "documentComment": "This SPDX document identifies the exact C23-selected installer and the explicit policy components selected by the release process. It is release evidence, not a Host installation claim.",
        "packages": packages,
        "relationships": relationships,
    }


def _build_notices(
    plan: Mapping[str, Any], installer: Mapping[str, str], components: tuple[Mapping[str, str], ...]
) -> str:
    lines = [
        "# VitalServer Runtime Platform third-party notices",
        "",
        "This notice set is bound to the following C23-selected installer artifact:",
        "",
        "- Platform: " + plan["platform"],
        "- Installer: " + installer["fileName"],
        "- Product version: " + installer["productVersion"],
        "- SHA-256: " + installer["sha256"],
        "",
        "The release process explicitly selected the following policy components. Their source and declared license are retained so a reviewer can distinguish them from unselected repository dependencies.",
        "",
    ]
    for component in components:
        lines.extend(
            [
                "## " + component["name"] + " " + component["version"],
                "",
                "- Component ID: " + component["id"],
                "- Declared license: " + component["license"],
                "- Source declaration: " + component["source"],
                "- Notice classification: " + component["noticeStatus"],
                "",
            ]
        )
    return "\n".join(lines)


def _publish(
    output_directory: Path,
    sbom: Mapping[str, Any],
    notices: str,
    plan: Mapping[str, Any],
    installer: Mapping[str, str],
    composition: ReleaseArtifactSBOMAndNoticesComposition,
) -> Mapping[str, Any]:
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(
        tempfile.mkdtemp(
            prefix="." + output_directory.name + ".compose-", dir=output_directory.parent
        )
    )
    try:
        sbom_path = temporary / "release-artifact.spdx.json"
        notices_path = temporary / "THIRD_PARTY_NOTICES.md"
        sbom_path.write_text(_canonical_json(sbom) + "\n", encoding="utf-8")
        notices_path.write_text(notices, encoding="utf-8")
        evidence = {
            "schemaVersion": "v1",
            "evidenceKind": "release-artifact-sbom-and-notices",
            "stage": "sbom-and-notices",
            "recordedAt": composition.recorded_at,
            "runner": {
                "kind": _RUNNER_KIND_BY_PLATFORM[plan["platform"]],
                "id": composition.runner_id,
            },
            "releaseDeliveryPlan": {
                "id": plan["id"],
                "platform": plan["platform"],
                "providerKind": plan["providerKind"],
                "productVersion": plan["productVersion"],
            },
            "observedInstallerArtifact": {
                **installer,
                "observedAt": composition.recorded_at,
            },
            "sbom": {
                "fileName": sbom_path.name,
                "sha256": _sha256_file(sbom_path),
            },
            "notices": {
                "fileName": notices_path.name,
                "sha256": _sha256_file(notices_path),
            },
        }
        (temporary / "sbom-and-notices-evidence.json").write_text(
            _canonical_json(evidence) + "\n", encoding="utf-8"
        )
        evidence_path = temporary / "sbom-and-notices-evidence.json"
        c24_proof = {
            "planId": plan["id"],
            "platform": plan["platform"],
            "providerKind": plan["providerKind"],
            "stage": "sbom-and-notices",
            "status": "verified",
            "recordedAt": composition.recorded_at,
            "runner": {
                "kind": _RUNNER_KIND_BY_PLATFORM[plan["platform"]],
                "id": composition.runner_id,
            },
            "evidence": {
                "uri": (output_directory / evidence_path.name).as_uri(),
                "sha256": _sha256_file(evidence_path),
            },
            "observedInstallerArtifact": installer,
        }
        (temporary / "release-delivery-proof-fragment.json").write_text(
            _canonical_json({"schemaVersion": "v1", "proofs": [c24_proof]}) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, output_directory)
        return c24_proof
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def _required_object(value: Mapping[str, Any], key: str, label: str) -> Mapping[str, Any]:
    candidate = value.get(key)
    if not isinstance(candidate, dict):
        raise ReleaseArtifactSBOMAndNoticesError(label + " requires object " + key)
    return candidate


def _required_string(value: Mapping[str, Any], key: str, label: str) -> str:
    candidate = value.get(key)
    if not isinstance(candidate, str) or not candidate:
        raise ReleaseArtifactSBOMAndNoticesError(label + " requires non-empty " + key)
    return candidate


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ReleaseArtifactSBOMAndNoticesError(
            "read installer or evidence artifact for SHA-256: " + str(error)
        ) from error
    return digest.hexdigest()


def _canonical_json(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True)


def _parse_arguments(arguments: Sequence[str] | None = None) -> ReleaseArtifactSBOMAndNoticesComposition:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-delivery-plans-document", required=True, type=Path)
    parser.add_argument("--release-delivery-plan-id", required=True)
    parser.add_argument("--installer-artifact", required=True, type=Path)
    parser.add_argument("--component-policy", required=True, type=Path)
    parser.add_argument("--component-id", required=True, action="append", dest="component_ids")
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--runner-id", required=True)
    parser.add_argument("--recorded-at", required=True)
    parsed = parser.parse_args(arguments)
    return ReleaseArtifactSBOMAndNoticesComposition(
        release_delivery_plans_document=parsed.release_delivery_plans_document,
        release_delivery_plan_id=parsed.release_delivery_plan_id,
        installer_artifact=parsed.installer_artifact,
        component_policy=parsed.component_policy,
        component_ids=tuple(parsed.component_ids),
        output_directory=parsed.output_directory,
        runner_id=parsed.runner_id,
        recorded_at=parsed.recorded_at,
    )


def main(arguments: Sequence[str] | None = None) -> int:
    try:
        result = compose_release_artifact_sbom_and_notices(_parse_arguments(arguments))
    except ReleaseArtifactSBOMAndNoticesError as error:
        print("release artifact SBOM/notices composition failed: " + str(error))
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
