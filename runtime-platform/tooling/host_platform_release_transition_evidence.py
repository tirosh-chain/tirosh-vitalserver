#!/usr/bin/env python3
"""Bind a C24 Host-platform transition claim to the real update contracts.

This is a release-process verifier, not an updater and not a Host Agent state
store. A C29 journal, C28 report, or C55 receipt alone proves only the fact its
owner recorded. This tool preserves their correlation and byte identities so a
clean-Host runner can later combine them with fresh OS observations. It never
turns internal receipts directly into a C24 ``verified`` proof.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import ntpath
import os
from pathlib import Path
import posixpath
import tempfile
import sys
from typing import Any, Mapping, Sequence

from tooling.product_delivery_release_plan import (
    ProductDeliveryReleasePlanError,
    load_selected_release_delivery_plan,
)
from tooling.contracts import ContractRepository, ContractToolError


class HostPlatformReleaseTransitionEvidenceError(RuntimeError):
    """A C29/C28/C55 transition fact is missing, invalid, or uncorrelated."""


HOST_PLATFORM_LAYER = "host-platform"
UPDATE_STAGE = "update"
ROLLBACK_STAGE = "rollback"
CONTRACT_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class ObservedEvidenceInput:
    """Exact source bytes consumed by a release-evidence observation."""

    kind: str
    path: Path
    sha256: str


@dataclass(frozen=True)
class HostPlatformReleaseTransitionEvidence:
    """Verified C29/C28/C55/C48/C49 facts for one prospective C24 stage.

    The C23 target plan identifies the release the update attempted. It is not
    an assertion that the target or restored release is currently active; an
    OS clean-Host runner must observe that C48 fact separately.
    """

    stage: str
    release_delivery_plan_id: str
    platform: str
    provider_kind: str
    target_product_version: str
    update_id: str
    request_id: str
    bootstrap_envelope_id: str
    update_specification_sha256: str
    host_platform_artifact_sha256: str
    inputs: tuple[ObservedEvidenceInput, ...]
    rollback_evidence: Mapping[str, str] | None
    observed_installation_id: str
    observed_release_id: str
    observed_product_version: str
    observed_package_identifier: str
    observed_at: str


def inspect_host_platform_update_transition(
    release_delivery_plans_document: Path,
    release_delivery_plan_id: str,
    host_update_journal_path: Path,
    host_platform_effect_receipt_path: Path,
    host_installation_manifest_path: Path,
    host_installation_footprint_path: Path,
) -> HostPlatformReleaseTransitionEvidence:
    """Verify a succeeded C29/C28/C55 apply and C48/C49 installed result."""

    target_plan = load_release_plan(release_delivery_plans_document, release_delivery_plan_id)
    journal, journal_input = read_evidence_input(host_update_journal_path, "host-update-journal")
    receipt, receipt_input = read_evidence_input(host_platform_effect_receipt_path, "host-platform-apply-effect-receipt")
    validate_contract_document("host-update-journal.schema.json", journal, "C29 journal")
    validate_contract_document(
        "staged-update-layer-effect-receipt.schema.json", receipt, "C55 apply receipt"
    )
    observed_installation, installation_inputs = read_host_installation_observation(
        host_installation_manifest_path,
        host_installation_footprint_path,
        target_plan,
        require_target_product_version=True,
    )
    correlation = validate_common_journal_correlation(journal, target_plan)
    report = required_object(journal.get("executionReport"), "C29 executionReport")
    validate_execution_report_correlation(report, correlation)
    if journal.get("state") != "succeeded" or report.get("state") != "succeeded":
        raise HostPlatformReleaseTransitionEvidenceError("C24 update transition requires C29 and C28 state succeeded")
    host_platform_evidence = required_host_platform_apply_evidence(report)
    artifact_sha256 = required_sha256(host_platform_evidence.get("artifactSha256"), "C28 host-platform artifact SHA-256")
    validate_effect_receipt(
        receipt,
        correlation,
        operation="apply",
        expected_artifact_sha256=artifact_sha256,
        expected_evidence=required_evidence_reference(host_platform_evidence.get("evidence"), "C28 host-platform evidence"),
    )
    return transition_evidence(
        UPDATE_STAGE,
        target_plan,
        correlation,
        artifact_sha256,
        (journal_input, receipt_input, *installation_inputs),
        None,
        observed_installation,
    )


def inspect_host_platform_rollback_transition(
    release_delivery_plans_document: Path,
    release_delivery_plan_id: str,
    host_update_journal_path: Path,
    host_platform_rollback_effect_receipt_path: Path,
    host_installation_manifest_path: Path,
    host_installation_footprint_path: Path,
) -> HostPlatformReleaseTransitionEvidence:
    """Verify a failed C29 update with succeeded C28/C55 rollback.

    C28 aggregates rollback outcomes rather than embedding each receipt, so
    the separate C55 rollback receipt is mandatory. C48/C49 then prove the
    actual restored Host release, which need not have C23's attempted target
    product version.
    """

    target_plan = load_release_plan(release_delivery_plans_document, release_delivery_plan_id)
    journal, journal_input = read_evidence_input(host_update_journal_path, "host-update-journal")
    receipt, receipt_input = read_evidence_input(host_platform_rollback_effect_receipt_path, "host-platform-rollback-effect-receipt")
    validate_contract_document("host-update-journal.schema.json", journal, "C29 journal")
    validate_contract_document(
        "staged-update-layer-effect-receipt.schema.json", receipt, "C55 rollback receipt"
    )
    observed_installation, installation_inputs = read_host_installation_observation(
        host_installation_manifest_path,
        host_installation_footprint_path,
        target_plan,
        require_target_product_version=False,
    )
    correlation = validate_common_journal_correlation(journal, target_plan)
    report = required_object(journal.get("executionReport"), "C29 executionReport")
    validate_execution_report_correlation(report, correlation)
    if journal.get("state") != "failed" or report.get("state") != "failed":
        raise HostPlatformReleaseTransitionEvidenceError("C24 rollback transition requires failed C29 and failed C28 update result")
    rollback = required_object(report.get("rollback"), "C28 rollback")
    if rollback.get("state") != "succeeded":
        raise HostPlatformReleaseTransitionEvidenceError("C24 rollback transition requires C28 rollback state succeeded")
    rollback_evidence = required_evidence_reference(rollback.get("evidence"), "C28 rollback evidence")
    artifact_sha256 = required_sha256(receipt.get("artifactSha256"), "C55 rollback artifact SHA-256")
    validate_effect_receipt(
        receipt,
        correlation,
        operation="rollback",
        expected_artifact_sha256=artifact_sha256,
        expected_evidence=None,
    )
    return transition_evidence(
        ROLLBACK_STAGE,
        target_plan,
        correlation,
        artifact_sha256,
        (journal_input, receipt_input, *installation_inputs),
        rollback_evidence,
        observed_installation,
    )


def transition_evidence(
    stage: str,
    target_plan: Mapping[str, Any],
    correlation: Mapping[str, str],
    artifact_sha256: str,
    inputs: tuple[ObservedEvidenceInput, ...],
    rollback_evidence: Mapping[str, str] | None,
    observed_installation: Mapping[str, str],
) -> HostPlatformReleaseTransitionEvidence:
    return HostPlatformReleaseTransitionEvidence(
        stage=stage,
        release_delivery_plan_id=required_identifier(target_plan.get("id"), "C23 release delivery plan ID"),
        platform=required_identifier(target_plan.get("platform"), "C23 platform"),
        provider_kind=required_identifier(target_plan.get("providerKind"), "C23 provider kind"),
        target_product_version=required_identifier(target_plan.get("productVersion"), "C23 product version"),
        update_id=correlation["updateId"],
        request_id=correlation["requestId"],
        bootstrap_envelope_id=correlation["bootstrapEnvelopeId"],
        update_specification_sha256=correlation["updateSpecificationSha256"],
        host_platform_artifact_sha256=artifact_sha256,
        inputs=inputs,
        rollback_evidence=rollback_evidence,
        observed_installation_id=observed_installation["installationId"],
        observed_release_id=observed_installation["releaseId"],
        observed_product_version=observed_installation["productVersion"],
        observed_package_identifier=observed_installation["packageIdentifier"],
        observed_at=observed_installation["observedAt"],
    )


def release_transition_evidence_document(evidence: HostPlatformReleaseTransitionEvidence) -> Mapping[str, Any]:
    """Render immutable input for a matching OS C24 evidence runner."""

    document: dict[str, Any] = {
        "schemaVersion": "v1",
        "evidenceKind": "host-platform-release-transition",
        "stage": evidence.stage,
        "releaseDeliveryPlanId": evidence.release_delivery_plan_id,
        "platform": evidence.platform,
        "providerKind": evidence.provider_kind,
        "targetProductVersion": evidence.target_product_version,
        "update": {
            "updateId": evidence.update_id,
            "requestId": evidence.request_id,
            "bootstrapEnvelopeId": evidence.bootstrap_envelope_id,
            "updateSpecificationSha256": evidence.update_specification_sha256,
            "hostPlatformArtifactSha256": evidence.host_platform_artifact_sha256,
        },
        "observedInputs": [
            {"kind": item.kind, "uri": item.path.as_uri(), "sha256": item.sha256}
            for item in evidence.inputs
        ],
        "observedHostInstallation": {
            "installationId": evidence.observed_installation_id,
            "releaseId": evidence.observed_release_id,
            "productVersion": evidence.observed_product_version,
            "packageIdentifier": evidence.observed_package_identifier,
            "observedAt": evidence.observed_at,
        },
    }
    if evidence.rollback_evidence is not None:
        document["rollbackEvidence"] = dict(evidence.rollback_evidence)
    return document


def write_new_release_transition_evidence(
    output_path: Path, evidence: HostPlatformReleaseTransitionEvidence
) -> tuple[Path, str]:
    """Atomically create a new evidence document and return its digest."""

    if not output_path.is_absolute() or not output_path.parent.is_dir():
        raise HostPlatformReleaseTransitionEvidenceError("release transition evidence output must be absolute with an existing parent")
    if output_path.exists() or output_path.is_symlink():
        raise HostPlatformReleaseTransitionEvidenceError("release transition evidence output must be a new non-symlink path")
    payload = canonical_json(release_transition_evidence_document(evidence)).encode("utf-8")
    descriptor, temporary_path = tempfile.mkstemp(prefix=".release-transition-evidence-", dir=output_path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, output_path)
    except OSError as error:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise HostPlatformReleaseTransitionEvidenceError("release transition evidence write failed: " + str(error)) from error
    return output_path, hashlib.sha256(payload).hexdigest()


def load_release_plan(path: Path, plan_id: str) -> Mapping[str, Any]:
    try:
        return load_selected_release_delivery_plan(path, plan_id)
    except ProductDeliveryReleasePlanError as error:
        raise HostPlatformReleaseTransitionEvidenceError(str(error)) from error


def read_evidence_input(path: Path, kind: str) -> tuple[Mapping[str, Any], ObservedEvidenceInput]:
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise HostPlatformReleaseTransitionEvidenceError(kind + " evidence input must be one absolute regular non-symlink file")
    try:
        payload = path.read_bytes()
        document = json.loads(payload)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise HostPlatformReleaseTransitionEvidenceError(kind + " evidence input is unreadable: " + str(error)) from error
    if not isinstance(document, dict):
        raise HostPlatformReleaseTransitionEvidenceError(kind + " evidence input must contain one JSON object")
    return document, ObservedEvidenceInput(kind, path, hashlib.sha256(payload).hexdigest())


def validate_contract_document(schema_name: str, document: Mapping[str, Any], label: str) -> None:
    """Require the exact owning C29/C55 contract before reading its fields."""

    try:
        repository = ContractRepository(CONTRACT_ROOT)
        repository.load()
        findings = repository.validate_instance(schema_name, document)
    except ContractToolError as error:
        raise HostPlatformReleaseTransitionEvidenceError(
            label + " contract source is unavailable: " + str(error)
        ) from error
    if findings:
        raise HostPlatformReleaseTransitionEvidenceError(
            label + " violates " + schema_name + ": " + "; ".join(findings)
        )


def read_host_installation_observation(
    manifest_path: Path,
    footprint_path: Path,
    target_plan: Mapping[str, Any],
    *,
    require_target_product_version: bool,
) -> tuple[Mapping[str, str], tuple[ObservedEvidenceInput, ObservedEvidenceInput]]:
    """Read independently captured C48/C49 facts and require their identity.

    This is a release-process reader: it does not invoke a Host manager, infer
    an activation target, or accept a package receipt as a substitute for the
    native C49 observation.
    """

    manifest, manifest_input = read_evidence_input(manifest_path, "host-installation-manifest")
    footprint, footprint_input = read_evidence_input(footprint_path, "host-installation-footprint")
    validate_contract_document(
        "host-product-installation-manifest.schema.json", manifest, "C48 Host installation manifest"
    )
    validate_contract_document(
        "host-installation-footprint.schema.json", footprint, "C49 Host installation footprint"
    )
    return (
        validate_host_installation_observation(
            manifest,
            footprint,
            target_plan,
            require_target_product_version=require_target_product_version,
        ),
        (manifest_input, footprint_input),
    )


def validate_host_installation_observation(
    manifest: Mapping[str, Any],
    footprint: Mapping[str, Any],
    target_plan: Mapping[str, Any],
    *,
    require_target_product_version: bool,
) -> Mapping[str, str]:
    """Require an active, byte-matched C48 slot in a native C49 observation."""

    platform = required_identifier(manifest.get("platform"), "C48 platform")
    target_platform = required_identifier(target_plan.get("platform"), "C23 platform")
    if platform != target_platform:
        raise HostPlatformReleaseTransitionEvidenceError("C48 platform does not match selected C23 release delivery plan")
    release = required_object(manifest.get("release"), "C48 release")
    package = required_object(manifest.get("package"), "C48 package")
    immutable_payload = required_object(manifest.get("immutablePayload"), "C48 immutablePayload")
    activation = required_object(manifest.get("activation"), "C48 activation")
    installation_id = required_identifier(manifest.get("installationId"), "C48 installation ID")
    release_id = required_identifier(release.get("id"), "C48 release ID")
    product_version = required_identifier(release.get("productVersion"), "C48 release product version")
    package_identifier = required_identifier(package.get("identifier"), "C48 package identifier")
    package_product_version = required_identifier(package.get("productVersion"), "C48 package product version")
    if package_product_version != product_version:
        raise HostPlatformReleaseTransitionEvidenceError("C48 package product version does not match C48 release product version")
    if require_target_product_version and product_version != target_plan.get("productVersion"):
        raise HostPlatformReleaseTransitionEvidenceError("C48 observed product version does not match selected C23 release delivery plan")
    if footprint.get("installationId") != installation_id:
        raise HostPlatformReleaseTransitionEvidenceError("C49 installation ID does not match C48")
    if footprint.get("expectedReleaseId") != release_id:
        raise HostPlatformReleaseTransitionEvidenceError("C49 expected release ID does not match C48")
    if footprint.get("platform") != platform:
        raise HostPlatformReleaseTransitionEvidenceError("C49 platform does not match C48")

    package_receipt = required_object(footprint.get("packageReceipt"), "C49 package receipt")
    if package_receipt.get("state") != "installed":
        raise HostPlatformReleaseTransitionEvidenceError("C49 package receipt must report installed")
    if package_receipt.get("identifier") != package_identifier:
        raise HostPlatformReleaseTransitionEvidenceError("C49 package receipt identifier does not match C48")
    if package_receipt.get("productVersion") != package_product_version:
        raise HostPlatformReleaseTransitionEvidenceError("C49 package receipt product version does not match C48")

    release_catalog = required_object(footprint.get("releaseCatalog"), "C49 release catalog")
    if release_catalog.get("releaseCatalogPath") != immutable_payload.get("releaseCatalogPath"):
        raise HostPlatformReleaseTransitionEvidenceError("C49 release catalog path does not match C48")
    if release_catalog.get("state") not in {"only-expected-release", "contains-other-releases"}:
        raise HostPlatformReleaseTransitionEvidenceError("C49 release catalog does not prove an expected active release catalog")
    release_ids = release_catalog.get("releaseIds")
    if not isinstance(release_ids, list) or release_id not in release_ids:
        raise HostPlatformReleaseTransitionEvidenceError("C49 release catalog does not contain the C48 release ID")

    immutable_release = required_object(footprint.get("immutableRelease"), "C49 immutable release")
    if immutable_release.get("state") != "matching" or immutable_release.get("releaseRootPath") != immutable_payload.get("releaseRootPath"):
        raise HostPlatformReleaseTransitionEvidenceError("C49 immutable release does not match C48")
    activation_observation = required_object(footprint.get("activation"), "C49 activation")
    if activation_observation.get("state") != "points-to-expected-release":
        raise HostPlatformReleaseTransitionEvidenceError("C49 activation does not point to the expected C48 release")
    if activation_observation.get("currentReleaseLinkPath") != activation.get("currentReleaseLinkPath") or activation_observation.get("observedTargetPath") != activation.get("expectedReleaseRootPath"):
        raise HostPlatformReleaseTransitionEvidenceError("C49 activation identity does not match C48")

    validate_required_service_observations(manifest, footprint)
    validate_mutable_store_observations(manifest, footprint)
    journal_path, receipt_path = declared_transaction_paths(manifest)
    transaction = required_object(footprint.get("installationTransaction"), "C49 installation transaction")
    if transaction.get("state") != "completed":
        raise HostPlatformReleaseTransitionEvidenceError("C49 installation transaction must be completed after a Host-platform transition")
    if transaction.get("journalPath") != journal_path or transaction.get("receiptPath") != receipt_path:
        raise HostPlatformReleaseTransitionEvidenceError("C49 installation transaction paths do not match the declared C48 store")
    return {
        "installationId": installation_id,
        "releaseId": release_id,
        "productVersion": product_version,
        "packageIdentifier": package_identifier,
        "observedAt": required_identifier(footprint.get("observedAt"), "C49 observedAt"),
    }


def validate_required_service_observations(manifest: Mapping[str, Any], footprint: Mapping[str, Any]) -> None:
    declared = manifest.get("requiredServices")
    observed = footprint.get("requiredServices")
    if not isinstance(declared, list) or not isinstance(observed, list):
        raise HostPlatformReleaseTransitionEvidenceError("C48/C49 required services must be arrays")
    declared_by_role = {item.get("role"): item for item in declared if isinstance(item, dict)}
    observed_by_role = {item.get("role"): item for item in observed if isinstance(item, dict)}
    if set(declared_by_role) != set(observed_by_role) or len(declared_by_role) != len(declared) or len(observed_by_role) != len(observed):
        raise HostPlatformReleaseTransitionEvidenceError("C49 required service roles do not exactly match C48")
    for role, declared_service in declared_by_role.items():
        observed_service = observed_by_role[role]
        if observed_service.get("name") != declared_service.get("name"):
            raise HostPlatformReleaseTransitionEvidenceError("C49 required service name does not match C48 for role " + str(role))
        if observed_service.get("state") != "registered" or observed_service.get("definitionState") != "matching":
            raise HostPlatformReleaseTransitionEvidenceError("C49 required service is not registered with matching definition for role " + str(role))


def validate_mutable_store_observations(manifest: Mapping[str, Any], footprint: Mapping[str, Any]) -> None:
    declared = manifest.get("mutableStores")
    observed = footprint.get("mutableStores")
    if not isinstance(declared, list) or not isinstance(observed, list):
        raise HostPlatformReleaseTransitionEvidenceError("C48/C49 mutable stores must be arrays")
    declared_by_id = {item.get("id"): item for item in declared if isinstance(item, dict)}
    observed_by_id = {item.get("id"): item for item in observed if isinstance(item, dict)}
    if set(declared_by_id) != set(observed_by_id) or len(declared_by_id) != len(declared) or len(observed_by_id) != len(observed):
        raise HostPlatformReleaseTransitionEvidenceError("C49 mutable store IDs do not exactly match C48")
    for store_id, observation in observed_by_id.items():
        if observation.get("state") == "unreadable":
            raise HostPlatformReleaseTransitionEvidenceError("C49 mutable store is unreadable: " + str(store_id))
    transaction_store = observed_by_id.get("installation-manager-journal")
    if not isinstance(transaction_store, dict) or transaction_store.get("state") != "compatible":
        raise HostPlatformReleaseTransitionEvidenceError("C49 C50 transaction store is not compatible")


def declared_transaction_paths(manifest: Mapping[str, Any]) -> tuple[str, str]:
    stores = manifest.get("mutableStores")
    if not isinstance(stores, list):
        raise HostPlatformReleaseTransitionEvidenceError("C48 mutable stores must be an array")
    matches = [
        store
        for store in stores
        if isinstance(store, dict)
        and store.get("id") == "installation-manager-journal"
        and store.get("owner") == "host-installation-manager"
        and store.get("kind") == "directory"
        and store.get("retention") == "purge-only-by-explicit-command"
    ]
    if len(matches) != 1 or not isinstance(matches[0].get("path"), str) or not matches[0]["path"]:
        raise HostPlatformReleaseTransitionEvidenceError("C48 must declare exactly one Host Installation Manager C50 transaction store")
    join = ntpath.join if manifest.get("platform") == "windows" else posixpath.join
    return (
        join(matches[0]["path"], "current-transaction.json"),
        join(matches[0]["path"], "latest-installation-receipt.json"),
    )


def validate_common_journal_correlation(journal: Mapping[str, Any], target_plan: Mapping[str, Any]) -> Mapping[str, str]:
    if journal.get("schemaVersion") != "v1":
        raise HostPlatformReleaseTransitionEvidenceError("C29 journal schemaVersion must be v1")
    update_id = required_identifier(journal.get("id"), "C29 update ID")
    request_id = required_identifier(journal.get("requestId"), "C29 request ID")
    bootstrap_envelope_id = required_identifier(journal.get("bootstrapEnvelopeId"), "C29 bootstrap envelope ID")
    update_specification_sha256 = required_sha256(journal.get("updateSpecificationSha256"), "C29 update specification SHA-256")
    target_release = required_object(journal.get("targetRelease"), "C29 targetRelease")
    if target_release.get("productVersion") != target_plan.get("productVersion"):
        raise HostPlatformReleaseTransitionEvidenceError("C29 target product version does not match selected C23 release delivery plan")
    bootstrap = required_object(journal.get("bootstrapEnvelope"), "C29 bootstrapEnvelope")
    target = required_object(bootstrap.get("target"), "C25 bootstrap target")
    if target.get("platform") != target_plan.get("platform"):
        raise HostPlatformReleaseTransitionEvidenceError("C25 bootstrap platform does not match selected C23 release delivery plan")
    if bootstrap.get("id") != bootstrap_envelope_id:
        raise HostPlatformReleaseTransitionEvidenceError("C29 bootstrap envelope ID does not match embedded C25 bootstrap envelope")
    return {"updateId": update_id, "requestId": request_id, "bootstrapEnvelopeId": bootstrap_envelope_id, "updateSpecificationSha256": update_specification_sha256}


def validate_execution_report_correlation(report: Mapping[str, Any], correlation: Mapping[str, str]) -> None:
    if report.get("schemaVersion") != "v1":
        raise HostPlatformReleaseTransitionEvidenceError("C28 report schemaVersion must be v1")
    for field in ("updateId", "requestId", "bootstrapEnvelopeId", "updateSpecificationSha256"):
        if report.get(field) != correlation[field]:
            raise HostPlatformReleaseTransitionEvidenceError("C28 report does not correlate " + field + " to C29")


def required_host_platform_apply_evidence(report: Mapping[str, Any]) -> Mapping[str, Any]:
    evidence = report.get("layerEvidence")
    if not isinstance(evidence, list):
        raise HostPlatformReleaseTransitionEvidenceError("C28 layerEvidence must be an array")
    matching = [item for item in evidence if isinstance(item, dict) and item.get("layer") == HOST_PLATFORM_LAYER]
    if len(matching) != 1:
        raise HostPlatformReleaseTransitionEvidenceError("C28 must contain exactly one host-platform layer evidence entry")
    if matching[0].get("state") != "succeeded":
        raise HostPlatformReleaseTransitionEvidenceError("C24 update transition requires succeeded C28 host-platform layer evidence")
    return matching[0]


def validate_effect_receipt(
    receipt: Mapping[str, Any], correlation: Mapping[str, str], *, operation: str,
    expected_artifact_sha256: str, expected_evidence: Mapping[str, str] | None,
) -> None:
    if receipt.get("schemaVersion") != "v1":
        raise HostPlatformReleaseTransitionEvidenceError("C55 receipt schemaVersion must be v1")
    if receipt.get("updateId") != correlation["updateId"]:
        raise HostPlatformReleaseTransitionEvidenceError("C55 receipt update ID does not match C29")
    if receipt.get("layer") != HOST_PLATFORM_LAYER:
        raise HostPlatformReleaseTransitionEvidenceError("C55 receipt layer must be host-platform")
    if receipt.get("operation") != operation or receipt.get("state") != "succeeded":
        raise HostPlatformReleaseTransitionEvidenceError("C55 receipt must report succeeded host-platform " + operation)
    if receipt.get("artifactSha256") != expected_artifact_sha256:
        raise HostPlatformReleaseTransitionEvidenceError("C55 receipt artifact SHA-256 does not match expected Host-platform artifact")
    receipt_evidence = required_evidence_reference(receipt.get("evidence"), "C55 receipt evidence")
    if expected_evidence is not None and receipt_evidence != expected_evidence:
        raise HostPlatformReleaseTransitionEvidenceError("C55 receipt evidence reference does not match C28 host-platform layer evidence")


def required_object(value: Any, name: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise HostPlatformReleaseTransitionEvidenceError(name + " must be an object")
    return value


def required_identifier(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise HostPlatformReleaseTransitionEvidenceError(name + " is required")
    return value


def required_sha256(value: Any, name: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise HostPlatformReleaseTransitionEvidenceError(name + " must be a lowercase SHA-256")
    return value


def required_evidence_reference(value: Any, name: str) -> Mapping[str, str]:
    document = required_object(value, name)
    kind, identifier = document.get("kind"), document.get("id")
    if set(document) != {"kind", "id"} or not isinstance(kind, str) or not kind or not isinstance(identifier, str) or not identifier:
        raise HostPlatformReleaseTransitionEvidenceError(name + " must contain exact non-empty kind and id")
    return {"kind": kind, "id": identifier}


def canonical_json(document: Any) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    for operation in (UPDATE_STAGE, ROLLBACK_STAGE):
        command = subparsers.add_parser(operation)
        command.add_argument("--release-delivery-plans-document", type=Path, required=True)
        command.add_argument("--release-delivery-plan-id", required=True)
        command.add_argument("--host-update-journal", type=Path, required=True)
        command.add_argument("--host-platform-effect-receipt", type=Path, required=True)
        command.add_argument("--host-installation-manifest", type=Path, required=True)
        command.add_argument("--host-installation-footprint", type=Path, required=True)
        command.add_argument("--output", type=Path, required=True)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        if parsed.operation == UPDATE_STAGE:
            evidence = inspect_host_platform_update_transition(
                parsed.release_delivery_plans_document,
                parsed.release_delivery_plan_id,
                parsed.host_update_journal,
                parsed.host_platform_effect_receipt,
                parsed.host_installation_manifest,
                parsed.host_installation_footprint,
            )
        else:
            evidence = inspect_host_platform_rollback_transition(
                parsed.release_delivery_plans_document,
                parsed.release_delivery_plan_id,
                parsed.host_update_journal,
                parsed.host_platform_effect_receipt,
                parsed.host_installation_manifest,
                parsed.host_installation_footprint,
            )
        output_path, digest = write_new_release_transition_evidence(parsed.output, evidence)
    except HostPlatformReleaseTransitionEvidenceError as error:
        print("host-platform release transition evidence failed: " + str(error), file=sys.stderr)
        return 2
    print(json.dumps({"output": str(output_path), "sha256": digest}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
