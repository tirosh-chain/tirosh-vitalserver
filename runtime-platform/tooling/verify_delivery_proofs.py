#!/usr/bin/env python3
"""Verify cross-platform delivery plans and explicit release-proof status."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from tooling.contracts import ContractRepository, ContractToolError, load_json


JSON_OBJECT = Dict[str, Any]
PROVIDER_BY_PLATFORM = {
    "macos": "macos-virtualization",
    "windows": "windows-hyperv-scm",
    "linux": "linux-kvm-libvirt-systemd",
}
RUNNER_BY_PLATFORM = {
    "macos": "macos-clean-host",
    "windows": "windows-clean-host",
    "linux": "linux-clean-host",
}


def validate(root: Path) -> Tuple[List[str], List[str]]:
    """Verify the checked-in C23 plan and C24 proof-set documents."""

    return validate_document_paths(
        root,
        root / "product" / "delivery" / "release-delivery-plans.v1.json",
        root / "product" / "delivery" / "release-delivery-proofs.v1.json",
    )


def validate_document_paths(
    root: Path,
    release_delivery_plans_document_path: Path,
    release_delivery_proof_set_document_path: Path,
) -> Tuple[List[str], List[str]]:
    """Verify explicitly selected C23/C24 document paths.

    A reviewed C24 candidate is a release output outside the source template.
    This function makes the candidate's plan/proof paths explicit instead of
    requiring a reviewer to copy it back into the checked-in template merely
    to run the release assertion.
    """

    try:
        plans_document = load_json(release_delivery_plans_document_path)
        proofs_document = load_json(release_delivery_proof_set_document_path)
    except ContractToolError as error:
        return [str(error)], []
    return validate_documents(root, plans_document, proofs_document)


def validate_reviewed_candidate_document_paths(
    root: Path,
    release_delivery_plans_document_path: Path,
    source_release_delivery_proof_set_document_path: Path,
    release_delivery_proof_set_document_path: Path,
    release_delivery_proof_attachment_review_document_path: Path,
) -> Tuple[List[str], List[str]]:
    """Verify that C74 binds one exact C24 candidate to its source template.

    C24 clean-Host runners write evidence outside the checked-in template. C74
    records the reviewed source, stage changes, and candidate identity. Normal
    development validation can inspect a pending template; the release gate
    must also reject an unreviewed or subsequently altered candidate.
    """

    findings, pending = validate_document_paths(
        root,
        release_delivery_plans_document_path,
        release_delivery_proof_set_document_path,
    )
    try:
        source_proof_set = load_json(source_release_delivery_proof_set_document_path)
        candidate_proof_set = load_json(release_delivery_proof_set_document_path)
        review_document = load_json(release_delivery_proof_attachment_review_document_path)
    except ContractToolError as error:
        return findings + [str(error)], pending

    repository = ContractRepository(root)
    try:
        repository.load()
    except ContractToolError as error:
        return findings + [str(error)], pending
    for error in repository.validate_instance(
        "release-delivery-proof-attachment-review.schema.json", review_document
    ):
        findings.append(f"release delivery proof attachment review: {error}")
    if findings:
        return findings, pending

    _validate_review_document_identity(
        source_release_delivery_proof_set_document_path,
        release_delivery_proof_set_document_path,
        review_document,
        findings,
    )
    _validate_reviewed_candidate_changes(
        source_proof_set,
        candidate_proof_set,
        review_document,
        findings,
    )
    return findings, pending


def validate_documents(
    root: Path,
    plans_document: JSON_OBJECT,
    proofs_document: JSON_OBJECT,
) -> Tuple[List[str], List[str]]:
    """Verify explicit C23/C24 documents supplied by a release workflow.

    The release-proof attachment workflow needs to verify a candidate immutable
    proof set before it publishes it.  Keeping that validation here avoids a
    second, weaker interpretation of C23/C24 in tooling.  This function does
    not read the documents or mutate them; callers retain ownership of their
    release input and output paths.
    """

    findings: List[str] = []
    pending: List[str] = []
    repository = ContractRepository(root)
    try:
        repository.load()
    except ContractToolError as error:
        return [str(error)], pending

    plans = plans_document.get("plans")
    if plans_document.get("schemaVersion") != "v1" or not isinstance(plans, list):
        return ["release delivery plans document must contain schemaVersion v1 and plans array"], pending
    proof_errors = repository.validate_instance("release-delivery-proof.schema.json", proofs_document)
    findings.extend(f"release delivery proofs: {error}" for error in proof_errors)
    if not isinstance(proofs_document.get("proofs"), list):
        return findings + ["release delivery proofs must contain proofs array"], pending

    plan_by_id: Dict[str, JSON_OBJECT] = {}
    for plan in plans:
        if not isinstance(plan, dict):
            findings.append("release delivery plan entry must be an object")
            continue
        for error in repository.validate_instance("release-delivery-plan.schema.json", plan):
            findings.append(f"release delivery plan: {error}")
        plan_id = plan.get("id")
        if not isinstance(plan_id, str):
            continue
        if plan_id in plan_by_id:
            findings.append(f"duplicate release delivery plan id: {plan_id}")
            continue
        platform = plan.get("platform")
        provider_kind = plan.get("providerKind")
        if PROVIDER_BY_PLATFORM.get(platform) != provider_kind:
            findings.append(f"plan {plan_id} has unsupported platform/provider pairing")
        plan_by_id[plan_id] = plan

    proof_by_key: Dict[Tuple[str, str], JSON_OBJECT] = {}
    for proof in proofs_document["proofs"]:
        if not isinstance(proof, dict):
            findings.append("release delivery proof entry must be an object")
            continue
        plan_id = proof.get("planId")
        stage = proof.get("stage")
        if not isinstance(plan_id, str) or not isinstance(stage, str):
            continue
        key = (plan_id, stage)
        if key in proof_by_key:
            findings.append(f"duplicate release delivery proof: {plan_id}/{stage}")
            continue
        proof_by_key[key] = proof
        plan = plan_by_id.get(plan_id)
        if plan is None:
            findings.append(f"proof {plan_id}/{stage} has no declared delivery plan")
            continue
        if proof.get("platform") != plan.get("platform") or proof.get("providerKind") != plan.get("providerKind"):
            findings.append(f"proof {plan_id}/{stage} does not match its declared platform/provider")
        status = proof.get("status")
        if status == "verified":
            runner = proof.get("runner")
            evidence = proof.get("evidence")
            expected_runner = RUNNER_BY_PLATFORM.get(plan.get("platform"))
            if not isinstance(runner, dict) or runner.get("kind") != expected_runner or not isinstance(runner.get("id"), str) or not runner["id"]:
                findings.append(f"verified proof {plan_id}/{stage} requires its matching clean-host runner identity")
            if not isinstance(evidence, dict) or not isinstance(evidence.get("uri"), str) or not evidence["uri"] or not isinstance(evidence.get("sha256"), str):
                findings.append(f"verified proof {plan_id}/{stage} requires evidence URI and SHA-256")
            validate_verified_installer_artifact_identity(
                plan_id,
                plan,
                proof,
                findings,
            )
            if (
                plan.get("platform") == "macos"
                and stage == "clean-install"
            ):
                validate_verified_macos_installer_receipt_observation(
                    plan_id,
                    plan,
                    proof,
                    findings,
                )
            if stage == "service-registration":
                validate_verified_host_service_registration_evidence(
                    plan_id,
                    plan,
                    proof,
                    findings,
                )
        else:
            pending.append(f"{plan_id}/{stage}={status}")

    for plan_id, plan in plan_by_id.items():
        stages = plan.get("requiredProofStages")
        if not isinstance(stages, list):
            continue
        for stage in stages:
            if (plan_id, stage) not in proof_by_key:
                findings.append(f"plan {plan_id} has no proof record for required stage {stage}")
    return findings, pending


def _validate_review_document_identity(
    source_proof_set_path: Path,
    candidate_proof_set_path: Path,
    review_document: JSON_OBJECT,
    findings: List[str],
) -> None:
    """Require C74 to name the exact source and output C24 document bytes."""

    source = review_document["sourceProofSet"]
    output = review_document["outputProofSet"]
    expected_source_uri = source_proof_set_path.resolve().as_uri()
    if source["uri"] != expected_source_uri:
        findings.append("C74 source proof-set URI does not match the selected source C24 document")
    observed_source_sha256 = _sha256_file(source_proof_set_path, findings, "source C24 proof set")
    if observed_source_sha256 is not None and source["sha256"] != observed_source_sha256:
        findings.append("C74 source proof-set SHA-256 does not match the selected source C24 document")
    if output["fileName"] != candidate_proof_set_path.name:
        findings.append("C74 output proof-set file name does not match the selected C24 candidate")
    observed_candidate_sha256 = _sha256_file(
        candidate_proof_set_path, findings, "selected C24 candidate"
    )
    if observed_candidate_sha256 is not None and output["sha256"] != observed_candidate_sha256:
        findings.append("C74 output proof-set SHA-256 does not match the selected C24 candidate")


def _validate_reviewed_candidate_changes(
    source_proof_set: JSON_OBJECT,
    candidate_proof_set: JSON_OBJECT,
    review_document: JSON_OBJECT,
    findings: List[str],
) -> None:
    """Ensure C74 lists exactly the C24 stages changed from its source.

    A review can settle only source ``pending`` facts. For a verified stage it
    must retain the candidate's exact evidence identity. Every other C24 edit
    is an unreviewed release declaration and is rejected.
    """

    source_by_key = _proofs_by_key(source_proof_set, "source C24 proof set", findings)
    candidate_by_key = _proofs_by_key(candidate_proof_set, "selected C24 candidate", findings)
    attached_by_key: Dict[Tuple[str, str], JSON_OBJECT] = {}
    for attached in review_document["attachedProofs"]:
        key = (attached["planId"], attached["stage"])
        if key in attached_by_key:
            findings.append(f"C74 contains duplicate attached proof: {key[0]}/{key[1]}")
            continue
        attached_by_key[key] = attached

    changed_keys = {
        key
        for key in set(source_by_key) | set(candidate_by_key)
        if source_by_key.get(key) != candidate_by_key.get(key)
    }
    reviewed_keys = set(attached_by_key)
    for plan_id, stage in sorted(changed_keys - reviewed_keys):
        findings.append(f"selected C24 candidate changes an unreviewed proof: {plan_id}/{stage}")
    for plan_id, stage in sorted(reviewed_keys - changed_keys):
        findings.append(f"C74 attached proof does not change the selected C24 candidate: {plan_id}/{stage}")

    for key in sorted(reviewed_keys & changed_keys):
        source_proof = source_by_key.get(key)
        candidate_proof = candidate_by_key.get(key)
        attached = attached_by_key[key]
        plan_id, stage = key
        if source_proof is None or candidate_proof is None:
            findings.append(f"C74 attached proof is absent from source or candidate C24: {plan_id}/{stage}")
            continue
        if source_proof.get("status") != "pending":
            findings.append(f"C74 may only replace a source pending proof: {plan_id}/{stage}")
        if candidate_proof.get("status") != attached["status"]:
            findings.append(f"C74 attached status does not match selected C24 candidate: {plan_id}/{stage}")
        if attached["status"] == "verified":
            candidate_evidence = candidate_proof.get("evidence")
            if candidate_evidence != attached.get("evidence"):
                findings.append(
                    f"C74 attached evidence does not match selected C24 candidate: {plan_id}/{stage}"
                )


def _proofs_by_key(
    proof_set: JSON_OBJECT, owner_description: str, findings: List[str]
) -> Dict[Tuple[str, str], JSON_OBJECT]:
    proofs = proof_set.get("proofs")
    if not isinstance(proofs, list):
        findings.append(f"{owner_description} must contain a proofs array")
        return {}
    by_key: Dict[Tuple[str, str], JSON_OBJECT] = {}
    for proof in proofs:
        if not isinstance(proof, dict):
            findings.append(f"{owner_description} proof entry must be an object")
            continue
        plan_id = proof.get("planId")
        stage = proof.get("stage")
        if not isinstance(plan_id, str) or not isinstance(stage, str):
            findings.append(f"{owner_description} proof entry has no plan/stage identity")
            continue
        key = (plan_id, stage)
        if key in by_key:
            findings.append(f"{owner_description} has duplicate proof: {plan_id}/{stage}")
            continue
        by_key[key] = proof
    return by_key


def _sha256_file(path: Path, findings: List[str], label: str) -> Optional[str]:
    """Read an explicit regular file without treating a symlink as evidence."""

    if not path.is_absolute():
        findings.append(f"{label} must be an absolute path")
        return None
    if path.is_symlink() or not path.is_file():
        findings.append(f"{label} must be a regular non-symlink file: {path}")
        return None
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        findings.append(f"could not read {label}: {error}")
        return None
    return digest.hexdigest()


def validate_verified_installer_artifact_identity(
    plan_id: str,
    release_delivery_plan: JSON_OBJECT,
    release_delivery_proof: JSON_OBJECT,
    findings: List[str],
) -> None:
    """Bind every verified C24 fact to the C23 installer it actually observed.

    C23 owns the intended installer artifact name, kind, and product version.
    A clean-host runner may only claim a stage as verified after it records the
    artifact identity it inspected or installed.  The runner's artifact digest
    remains an observation because C23 does not own built-byte identity.
    """

    intended_installer_artifact = release_delivery_plan.get(
        "intendedInstallerArtifact"
    )
    observed_installer_artifact = release_delivery_proof.get(
        "observedInstallerArtifact"
    )
    if not isinstance(intended_installer_artifact, dict):
        findings.append(
            f"plan {plan_id} intendedInstallerArtifact is unavailable for C24 verification"
        )
        return
    if not isinstance(observed_installer_artifact, dict):
        findings.append(
            f"verified proof {plan_id}/{release_delivery_proof.get('stage')} requires observedInstallerArtifact"
        )
        return
    if intended_installer_artifact.get("kind") != observed_installer_artifact.get(
        "kind"
    ):
        findings.append(
            f"verified proof {plan_id}/{release_delivery_proof.get('stage')} observed installer artifact kind does not match C23 intended installer artifact"
        )
    if intended_installer_artifact.get("expectedName") != observed_installer_artifact.get(
        "fileName"
    ):
        findings.append(
            f"verified proof {plan_id}/{release_delivery_proof.get('stage')} observed installer artifact fileName does not match C23 intended installer artifact"
        )
    if release_delivery_plan.get("productVersion") != observed_installer_artifact.get(
        "productVersion"
    ):
        findings.append(
            f"verified proof {plan_id}/{release_delivery_proof.get('stage')} observed installer artifact productVersion does not match C23 productVersion"
        )


def validate_verified_host_service_registration_evidence(
    plan_id: str,
    release_delivery_plan: JSON_OBJECT,
    release_delivery_proof: JSON_OBJECT,
    findings: List[str],
) -> None:
    """Bind verified C24 service facts to the C23 registrations they prove.

    C23 owns intended Host service registrations. C24 records an observation
    made by the matching clean Host runner; it is not allowed to name a
    different service, omit one of the required services, or infer a label
    from package layout.
    """

    expected_registrations = release_delivery_plan.get(
        "requiredHostServiceRegistrations"
    )
    observed_registrations = release_delivery_proof.get(
        "observedHostServiceRegistrations"
    )
    if not isinstance(expected_registrations, list):
        findings.append(
            f"plan {plan_id} requiredHostServiceRegistrations is unavailable for C24 service-registration verification"
        )
        return
    if not isinstance(observed_registrations, list):
        findings.append(
            f"verified proof {plan_id}/service-registration requires observedHostServiceRegistrations"
        )
        return
    expected_by_role = host_service_registration_by_role(
        expected_registrations,
        f"plan {plan_id}",
        findings,
    )
    observed_by_role = host_service_registration_by_role(
        observed_registrations,
        f"verified proof {plan_id}/service-registration",
        findings,
    )
    if set(expected_by_role) != set(observed_by_role):
        findings.append(
            f"verified proof {plan_id}/service-registration must observe exactly the C23 required Host service roles"
        )
        return
    for role, expected_registration in expected_by_role.items():
        observed_registration = observed_by_role[role]
        if (
            expected_registration.get("manager")
            != observed_registration.get("manager")
            or expected_registration.get("name")
            != observed_registration.get("name")
        ):
            findings.append(
                f"verified proof {plan_id}/service-registration {role} does not match its C23 required Host service registration"
            )
        if observed_registration.get("registrationState") != "registered":
            findings.append(
                f"verified proof {plan_id}/service-registration {role} must report registrationState registered"
            )


def validate_verified_macos_installer_receipt_observation(
    plan_id: str,
    release_delivery_plan: JSON_OBJECT,
    release_delivery_proof: JSON_OBJECT,
    findings: List[str],
) -> None:
    """Bind a verified macOS clean install to the C23 PKG receipt identity.

    A PKG file digest says which bytes the runner selected.  A macOS package
    receipt says which package installer registration the clean Host observed
    *after* the installer effect.  Neither fact may be guessed from the other.
    """

    observed_receipt = release_delivery_proof.get("observedMacOSInstallerReceipt")
    if not isinstance(observed_receipt, dict):
        findings.append(
            f"verified proof {plan_id}/clean-install requires observedMacOSInstallerReceipt"
        )
        return
    if (
        release_delivery_plan.get("macOSInstallerPackageIdentifier")
        != observed_receipt.get("packageIdentifier")
    ):
        findings.append(
            f"verified proof {plan_id}/clean-install observed macOS installer package identifier does not match C23 macOS installer package identifier"
        )
    if release_delivery_plan.get("productVersion") != observed_receipt.get(
        "productVersion"
    ):
        findings.append(
            f"verified proof {plan_id}/clean-install observed macOS installer receipt productVersion does not match C23 productVersion"
        )
    if observed_receipt.get("receiptState") != "installed":
        findings.append(
            f"verified proof {plan_id}/clean-install observed macOS installer receipt must report receiptState installed"
        )


def host_service_registration_by_role(
    registrations: List[Any],
    owner_description: str,
    findings: List[str],
) -> Dict[str, JSON_OBJECT]:
    """Index explicit Host service registrations without accepting ambiguous roles."""

    registrations_by_role: Dict[str, JSON_OBJECT] = {}
    for registration in registrations:
        if not isinstance(registration, dict):
            findings.append(
                f"{owner_description} Host service registration must be an object"
            )
            continue
        role = registration.get("role")
        if not isinstance(role, str):
            findings.append(
                f"{owner_description} Host service registration role is unavailable"
            )
            continue
        if role in registrations_by_role:
            findings.append(
                f"{owner_description} has duplicate Host service registration role {role}"
            )
            continue
        registrations_by_role[role] = registration
    return registrations_by_role


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--release-delivery-plans-document",
        type=Path,
        help="absolute C23 release-delivery plans document; defaults to the selected root's source document",
    )
    parser.add_argument(
        "--release-delivery-proof-set-document",
        type=Path,
        help="absolute C24 proof-set document; defaults to the selected root's source template",
    )
    parser.add_argument(
        "--source-release-delivery-proof-set-document",
        type=Path,
        help="absolute source C24 proof-set document that a supplied C74 review must bind",
    )
    parser.add_argument(
        "--release-delivery-proof-attachment-review-document",
        type=Path,
        help="absolute C74 review document required to release a reviewed C24 candidate",
    )
    parser.add_argument(
        "--require-verified",
        action="store_true",
        help="fail unless every declared required delivery stage has verified clean-host evidence",
    )
    arguments = parser.parse_args(argv)
    root = arguments.root.resolve()
    plans_document_path = (
        arguments.release_delivery_plans_document
        or root / "product" / "delivery" / "release-delivery-plans.v1.json"
    )
    proof_set_document_path = (
        arguments.release_delivery_proof_set_document
        or root / "product" / "delivery" / "release-delivery-proofs.v1.json"
    )
    source_proof_set_document_path = (
        arguments.source_release_delivery_proof_set_document
        or root / "product" / "delivery" / "release-delivery-proofs.v1.json"
    )
    for label, path in (
        ("release delivery plans document", plans_document_path),
        ("release delivery proof set document", proof_set_document_path),
    ):
        if not path.is_absolute():
            parser.error(label + " must be an absolute path")
    findings, pending = validate_document_paths(
        root, plans_document_path, proof_set_document_path
    )
    if arguments.release_delivery_proof_attachment_review_document is not None:
        review_document_path = arguments.release_delivery_proof_attachment_review_document
        if not review_document_path.is_absolute():
            parser.error("release delivery proof attachment review document must be an absolute path")
        if not source_proof_set_document_path.is_absolute():
            parser.error("source release delivery proof set document must be an absolute path")
        findings, pending = validate_reviewed_candidate_document_paths(
            root,
            plans_document_path,
            source_proof_set_document_path,
            proof_set_document_path,
            review_document_path,
        )
    if arguments.require_verified:
        canonical_source_proof_set_document_path = (
            root / "product" / "delivery" / "release-delivery-proofs.v1.json"
        )
        if source_proof_set_document_path.resolve() != canonical_source_proof_set_document_path:
            findings.append(
                "release-ready C74 review must bind the checked-in canonical C24 source proof set"
            )
        findings.extend(f"release proof is not verified: {label}" for label in pending)
        if arguments.release_delivery_proof_attachment_review_document is None:
            findings.append(
                "release-ready requires an explicit C74 release delivery proof attachment review document"
            )
    if findings:
        print("runtime-platform delivery proof verification failed:")
        for finding in findings:
            print(f"  {finding}")
        return 1
    if pending:
        print("runtime-platform delivery proof structure is valid; explicit pending proof:")
        for label in pending:
            print(f"  {label}")
        return 0
    print("runtime-platform delivery proof verification passed with all stages verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
