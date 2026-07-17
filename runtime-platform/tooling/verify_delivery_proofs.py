#!/usr/bin/env python3
"""Verify cross-platform delivery plans and explicit release-proof status."""

from __future__ import annotations

import argparse
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
    """Return structural failures and intentionally pending proof labels."""

    findings: List[str] = []
    pending: List[str] = []
    repository = ContractRepository(root)
    try:
        repository.load()
        plans_document = load_json(root / "product" / "delivery" / "release-delivery-plans.v1.json")
        proofs_document = load_json(root / "product" / "delivery" / "release-delivery-proofs.v1.json")
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
        "--require-verified",
        action="store_true",
        help="fail unless every declared required delivery stage has verified clean-host evidence",
    )
    arguments = parser.parse_args(argv)
    findings, pending = validate(arguments.root.resolve())
    if arguments.require_verified:
        findings.extend(f"release proof is not verified: {label}" for label in pending)
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
