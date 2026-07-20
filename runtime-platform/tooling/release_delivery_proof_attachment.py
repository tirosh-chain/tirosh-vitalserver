#!/usr/bin/env python3
"""Publish a reviewed, immutable C24 release-delivery proof-set candidate.

This Release-process application does not install a Host, operate a Guest, or
modify the checked-in C24 template.  It takes an explicit C23 plan document,
one source C24 proof set, reviewed proof fragments, and the exact evidence
material that the reviewer inspected.  It writes a *new* proof set and C74
review record into one previously absent output directory.

Only a source ``pending`` stage can be attached.  A fragment must settle that
stage as ``verified``, ``failed``, or ``unsupported``; a later workflow cannot
silently replace an existing terminal fact.  A verified proof additionally
requires caller-supplied evidence material whose bytes match the fragment's
declared SHA-256.  Thus a fragment's URI is not treated as proof by itself.
"""

from __future__ import annotations

import argparse
import copy
from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractRepository, ContractToolError, load_json
from tooling.verify_delivery_proofs import validate_documents


JSON_OBJECT = dict[str, Any]
PROOF_SET_FILE_NAME = "release-delivery-proofs.v1.json"
REVIEW_FILE_NAME = "release-delivery-proof-attachment-review.v1.json"
_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")


class ReleaseDeliveryProofAttachmentError(RuntimeError):
    """A reviewed C24 proof-set candidate cannot be safely published."""


@dataclass(frozen=True)
class ReviewedEvidenceMaterial:
    """Exact evidence bytes the release reviewer presents for one URI."""

    uri: str
    path: Path


@dataclass(frozen=True)
class ReleaseDeliveryProofAttachmentRequest:
    """All explicit input for one immutable C24 proof attachment review."""

    contract_root: Path
    release_delivery_plans_document: Path
    source_proof_set: Path
    proof_fragments: tuple[Path, ...]
    reviewed_evidence_materials: tuple[ReviewedEvidenceMaterial, ...]
    output_directory: Path
    review_id: str
    reviewer_id: str
    reviewed_at: str


def publish_reviewed_release_delivery_proof_set(
    request: ReleaseDeliveryProofAttachmentRequest,
) -> Mapping[str, Any]:
    """Review explicit fragments and publish one separate C24 proof-set candidate."""

    _validate_request_paths_and_review_identity(request)
    repository = ContractRepository(request.contract_root)
    try:
        repository.load()
        plans_document = load_json(request.release_delivery_plans_document)
        source_proof_set = load_json(request.source_proof_set)
    except ContractToolError as error:
        raise ReleaseDeliveryProofAttachmentError(str(error)) from error

    source_findings, _ = validate_documents(
        request.contract_root, plans_document, source_proof_set
    )
    if source_findings:
        raise ReleaseDeliveryProofAttachmentError(
            "source C24 proof set is invalid: " + "; ".join(source_findings)
        )

    reviewed_evidence_by_uri = _reviewed_evidence_by_uri(
        request.reviewed_evidence_materials
    )
    proof_fragments = _load_reviewed_proof_fragments(
        repository, request.proof_fragments
    )
    output_proof_set, attached_proofs = _attach_reviewed_proof_fragments(
        plans_document,
        source_proof_set,
        proof_fragments,
        reviewed_evidence_by_uri,
    )
    output_findings, _ = validate_documents(
        request.contract_root, plans_document, output_proof_set
    )
    if output_findings:
        raise ReleaseDeliveryProofAttachmentError(
            "reviewed C24 proof set is invalid: " + "; ".join(output_findings)
        )
    return _publish_output_directory(
        repository,
        request,
        output_proof_set,
        attached_proofs,
    )


def _validate_request_paths_and_review_identity(
    request: ReleaseDeliveryProofAttachmentRequest,
) -> None:
    if not request.contract_root.is_absolute() or not request.contract_root.is_dir():
        raise ReleaseDeliveryProofAttachmentError(
            "runtime-platform contract root must be an existing absolute directory"
        )
    for label, path in (
        ("C23 release delivery plans document", request.release_delivery_plans_document),
        ("source C24 proof set", request.source_proof_set),
    ):
        _require_absolute_regular_file(path, label)
    if not request.proof_fragments:
        raise ReleaseDeliveryProofAttachmentError("at least one reviewed proof fragment is required")
    for fragment in request.proof_fragments:
        _require_absolute_regular_file(fragment, "reviewed proof fragment")
    if not request.output_directory.is_absolute():
        raise ReleaseDeliveryProofAttachmentError(
            "C24 attachment output directory must be absolute"
        )
    if request.output_directory.exists() or request.output_directory.is_symlink():
        raise ReleaseDeliveryProofAttachmentError(
            "C24 attachment output directory must not already exist: "
            + str(request.output_directory)
        )
    if not request.output_directory.parent.is_dir():
        raise ReleaseDeliveryProofAttachmentError(
            "C24 attachment output directory parent must already exist: "
            + str(request.output_directory.parent)
        )
    for label, value in (("review ID", request.review_id), ("reviewer ID", request.reviewer_id)):
        if not _IDENTIFIER.fullmatch(value):
            raise ReleaseDeliveryProofAttachmentError(label + " is invalid")
    try:
        datetime.fromisoformat(request.reviewed_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ReleaseDeliveryProofAttachmentError(
            "reviewed-at must be an RFC3339 timestamp"
        ) from error


def _require_absolute_regular_file(path: Path, label: str) -> None:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise ReleaseDeliveryProofAttachmentError(
            label + " must be one absolute regular non-symlink file: " + str(path)
        )


def _reviewed_evidence_by_uri(
    materials: Sequence[ReviewedEvidenceMaterial],
) -> dict[str, Path]:
    by_uri: dict[str, Path] = {}
    for material in materials:
        if not material.uri:
            raise ReleaseDeliveryProofAttachmentError("reviewed evidence URI is required")
        if material.uri in by_uri:
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed evidence URI is duplicated: " + material.uri
            )
        _require_absolute_regular_file(material.path, "reviewed evidence material")
        by_uri[material.uri] = material.path
    return by_uri


def _load_reviewed_proof_fragments(
    repository: ContractRepository,
    fragment_paths: Sequence[Path],
) -> tuple[tuple[JSON_OBJECT, JSON_OBJECT], ...]:
    fragments: list[tuple[JSON_OBJECT, JSON_OBJECT]] = []
    seen_keys: set[tuple[str, str]] = set()
    for fragment_path in fragment_paths:
        try:
            document = load_json(fragment_path)
        except ContractToolError as error:
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed proof fragment cannot be read: " + str(error)
            ) from error
        if "proofs" in document:
            proof_set = document
        else:
            proof_set = {"schemaVersion": "v1", "proofs": [document]}
        validation_errors = repository.validate_instance(
            "release-delivery-proof.schema.json", proof_set
        )
        if validation_errors:
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed proof fragment is invalid: "
                + str(fragment_path)
                + ": "
                + "; ".join(validation_errors)
            )
        proofs = proof_set["proofs"]
        if not proofs:
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed proof fragment must contain at least one proof: "
                + str(fragment_path)
            )
        fragment_identity = {
            "uri": fragment_path.as_uri(),
            "sha256": _sha256_file(fragment_path),
        }
        for proof in proofs:
            assert isinstance(proof, dict)
            plan_id = proof["planId"]
            stage = proof["stage"]
            key = (plan_id, stage)
            if key in seen_keys:
                raise ReleaseDeliveryProofAttachmentError(
                    "reviewed proof fragments contain duplicate C24 stage: "
                    + plan_id
                    + "/"
                    + stage
                )
            seen_keys.add(key)
            fragments.append((copy.deepcopy(proof), fragment_identity))
    return tuple(fragments)


def _attach_reviewed_proof_fragments(
    plans_document: JSON_OBJECT,
    source_proof_set: JSON_OBJECT,
    proof_fragments: Sequence[tuple[JSON_OBJECT, JSON_OBJECT]],
    reviewed_evidence_by_uri: Mapping[str, Path],
) -> tuple[JSON_OBJECT, list[JSON_OBJECT]]:
    plan_by_id = _plans_by_id(plans_document)
    source_proofs = source_proof_set["proofs"]
    source_index = {
        (proof["planId"], proof["stage"]): index
        for index, proof in enumerate(source_proofs)
    }
    output_proof_set = copy.deepcopy(source_proof_set)
    used_evidence_uris: set[str] = set()
    attached_proofs: list[JSON_OBJECT] = []

    for fragment, fragment_identity in proof_fragments:
        plan_id = fragment["planId"]
        stage = fragment["stage"]
        key = (plan_id, stage)
        source_index_for_stage = source_index.get(key)
        if source_index_for_stage is None:
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed proof has no pending C24 source stage: " + plan_id + "/" + stage
            )
        plan = plan_by_id.get(plan_id)
        if plan is None or stage not in plan["requiredProofStages"]:
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed proof stage is not required by C23: " + plan_id + "/" + stage
            )
        source_proof = source_proofs[source_index_for_stage]
        if source_proof["status"] != "pending":
            raise ReleaseDeliveryProofAttachmentError(
                "C24 source stage is not pending and cannot be replaced: "
                + plan_id
                + "/"
                + stage
            )
        if fragment["status"] == "pending":
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed proof fragment must settle its pending C24 stage: "
                + plan_id
                + "/"
                + stage
            )
        if (
            fragment["platform"] != plan["platform"]
            or fragment["providerKind"] != plan["providerKind"]
        ):
            raise ReleaseDeliveryProofAttachmentError(
                "reviewed proof does not match C23 platform/provider: "
                + plan_id
                + "/"
                + stage
            )
        attached = {
            "planId": plan_id,
            "stage": stage,
            "status": fragment["status"],
            "proofFragment": fragment_identity,
        }
        if fragment["status"] == "verified":
            evidence = fragment["evidence"]
            evidence_uri = evidence["uri"]
            evidence_material = reviewed_evidence_by_uri.get(evidence_uri)
            if evidence_material is None:
                raise ReleaseDeliveryProofAttachmentError(
                    "verified C24 proof requires reviewed evidence material for URI: "
                    + evidence_uri
                )
            observed_sha256 = _sha256_file(evidence_material)
            if observed_sha256 != evidence["sha256"]:
                raise ReleaseDeliveryProofAttachmentError(
                    "reviewed evidence material SHA-256 does not match C24 proof: "
                    + evidence_uri
                )
            used_evidence_uris.add(evidence_uri)
            attached["evidence"] = {
                "uri": evidence_uri,
                "sha256": evidence["sha256"],
            }
        output_proof_set["proofs"][source_index_for_stage] = copy.deepcopy(fragment)
        attached_proofs.append(attached)

    unused_evidence_uris = set(reviewed_evidence_by_uri) - used_evidence_uris
    if unused_evidence_uris:
        raise ReleaseDeliveryProofAttachmentError(
            "reviewed evidence material has no verified C24 proof: "
            + ", ".join(sorted(unused_evidence_uris))
        )
    return output_proof_set, attached_proofs


def _plans_by_id(plans_document: JSON_OBJECT) -> dict[str, JSON_OBJECT]:
    plans = plans_document.get("plans")
    if not isinstance(plans, list):
        raise ReleaseDeliveryProofAttachmentError(
            "C23 release delivery plans must contain a plans array"
        )
    by_id: dict[str, JSON_OBJECT] = {}
    for plan in plans:
        if not isinstance(plan, dict) or not isinstance(plan.get("id"), str):
            raise ReleaseDeliveryProofAttachmentError(
                "C23 release delivery plan is not a readable object"
            )
        by_id[plan["id"]] = plan
    return by_id


def _publish_output_directory(
    repository: ContractRepository,
    request: ReleaseDeliveryProofAttachmentRequest,
    output_proof_set: JSON_OBJECT,
    attached_proofs: Sequence[JSON_OBJECT],
) -> Mapping[str, Any]:
    temporary_directory = Path(
        tempfile.mkdtemp(
            prefix="." + request.output_directory.name + ".review-",
            dir=request.output_directory.parent,
        )
    )
    try:
        proof_set_path = temporary_directory / PROOF_SET_FILE_NAME
        proof_set_path.write_text(_canonical_json(output_proof_set) + "\n", encoding="utf-8")
        review_document: JSON_OBJECT = {
            "schemaVersion": "v1",
            "reviewId": request.review_id,
            "reviewerId": request.reviewer_id,
            "reviewedAt": request.reviewed_at,
            "sourceProofSet": {
                "uri": request.source_proof_set.as_uri(),
                "sha256": _sha256_file(request.source_proof_set),
            },
            "attachedProofs": list(attached_proofs),
            "outputProofSet": {
                "fileName": PROOF_SET_FILE_NAME,
                "sha256": _sha256_file(proof_set_path),
            },
        }
        review_errors = repository.validate_instance(
            "release-delivery-proof-attachment-review.schema.json", review_document
        )
        if review_errors:
            raise ReleaseDeliveryProofAttachmentError(
                "C74 proof attachment review is invalid: " + "; ".join(review_errors)
            )
        review_path = temporary_directory / REVIEW_FILE_NAME
        review_path.write_text(_canonical_json(review_document) + "\n", encoding="utf-8")
        os.replace(temporary_directory, request.output_directory)
    except Exception:
        shutil.rmtree(temporary_directory, ignore_errors=True)
        raise
    return {
        "proofSetPath": str(request.output_directory / PROOF_SET_FILE_NAME),
        "proofSetSHA256": review_document["outputProofSet"]["sha256"],
        "reviewPath": str(request.output_directory / REVIEW_FILE_NAME),
        "reviewSHA256": _sha256_file(request.output_directory / REVIEW_FILE_NAME),
        "attachedProofCount": len(attached_proofs),
    }


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ReleaseDeliveryProofAttachmentError(
            "could not read release evidence material: " + str(error)
        ) from error
    return digest.hexdigest()


def _canonical_json(document: Mapping[str, Any]) -> str:
    return json.dumps(document, indent=2, sort_keys=True)


def _parse_reviewed_evidence_material(value: str) -> ReviewedEvidenceMaterial:
    uri, separator, raw_path = value.partition("=")
    if not separator or not uri or not raw_path:
        raise argparse.ArgumentTypeError(
            "reviewed evidence material must be EVIDENCE_URI=ABSOLUTE_FILE_PATH"
        )
    return ReviewedEvidenceMaterial(uri=uri, path=Path(raw_path))


def _parse_request(
    arguments: Sequence[str] | None = None,
) -> ReleaseDeliveryProofAttachmentRequest:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--runtime-platform-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    parser.add_argument("--release-delivery-plans-document", required=True, type=Path)
    parser.add_argument("--source-proof-set", required=True, type=Path)
    parser.add_argument("--proof-fragment", required=True, action="append", type=Path, dest="proof_fragments")
    parser.add_argument(
        "--reviewed-evidence-material",
        action="append",
        default=[],
        type=_parse_reviewed_evidence_material,
        dest="reviewed_evidence_materials",
        metavar="EVIDENCE_URI=ABSOLUTE_FILE_PATH",
    )
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--review-id", required=True)
    parser.add_argument("--reviewer-id", required=True)
    parser.add_argument("--reviewed-at", required=True)
    parsed = parser.parse_args(arguments)
    return ReleaseDeliveryProofAttachmentRequest(
        contract_root=parsed.runtime_platform_root,
        release_delivery_plans_document=parsed.release_delivery_plans_document,
        source_proof_set=parsed.source_proof_set,
        proof_fragments=tuple(parsed.proof_fragments),
        reviewed_evidence_materials=tuple(parsed.reviewed_evidence_materials),
        output_directory=parsed.output_directory,
        review_id=parsed.review_id,
        reviewer_id=parsed.reviewer_id,
        reviewed_at=parsed.reviewed_at,
    )


def main(arguments: Sequence[str] | None = None) -> int:
    try:
        result = publish_reviewed_release_delivery_proof_set(_parse_request(arguments))
    except ReleaseDeliveryProofAttachmentError as error:
        print("release delivery proof attachment failed: " + str(error))
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
