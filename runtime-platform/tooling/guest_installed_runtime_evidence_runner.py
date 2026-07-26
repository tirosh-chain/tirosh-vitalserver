#!/usr/bin/env python3
"""Collect C78 installed Guest boot, direct-upload, and reboot evidence.

The runner reads Guest state only through platformctl and the Host local-control
facade. It streams one explicitly selected .vital file through the public
Recorder upload endpoint and verifies the resulting Guest-owned Archive
lineage. It observes the Host boot session through one explicit sysctl
contract. It never reads Guest files, databases, processes, logs, or VM disk
contents.
"""

from __future__ import annotations

import argparse
from contextlib import closing
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
from typing import Any, Mapping, Sequence
from urllib.parse import urlparse

from tooling.contracts import ContractRepository


FIRST_BOOT_STAGE = "first-boot-checkpoint"
DIRECT_UPLOAD_STAGE = "direct-upload-lineage"
POST_REBOOT_STAGE = "post-reboot-identity"
STAGES = {FIRST_BOOT_STAGE, DIRECT_UPLOAD_STAGE, POST_REBOOT_STAGE}
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
RECORDER_UPLOAD_RECEIPT_TYPE = "recorder-vital-upload-source-receipt"


class GuestInstalledRuntimeEvidenceError(RuntimeError):
    """The C78 run, owner observation, or journal is invalid."""


@dataclass(frozen=True)
class CommandObservation:
    executable: Path
    arguments: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class EvidenceRun:
    run_id: str
    runner_id: str
    release_delivery_plan_id: str
    platformctl_executable: Path
    local_control_descriptor: Path
    sysctl_executable: Path
    contract_root: Path
    evidence_directory: Path
    created_at: str


@dataclass(frozen=True)
class StageRecord:
    stage: str
    status: str
    evidence_id: str
    evidence_path: Path
    evidence_sha256: str
    recorded_at: str


@dataclass(frozen=True)
class DirectUploadInputs:
    source_vital_file: Path
    edge_endpoint: str
    recorder_id: str
    reported_bed_name: str
    declared_recorder_code: str
    upload_id: str
    curl_executable: Path
    byte_size: int
    sha256: str


class Journal:
    def __init__(self, path: Path):
        self.path = path

    @classmethod
    def create(cls, path: Path, run: EvidenceRun) -> "Journal":
        validate_run(run)
        if not path.is_absolute() or path.exists() or not path.parent.is_dir():
            raise GuestInstalledRuntimeEvidenceError(
                "C78 journal must be a new absolute path with an existing parent"
            )
        with closing(sqlite3.connect(path)) as connection:
            with connection:
                connection.executescript(
                    """
                CREATE TABLE evidence_run (
                  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                  run_id TEXT NOT NULL,
                  runner_id TEXT NOT NULL,
                  release_delivery_plan_id TEXT NOT NULL,
                  platformctl_executable TEXT NOT NULL,
                  local_control_descriptor TEXT NOT NULL,
                  sysctl_executable TEXT NOT NULL,
                  contract_root TEXT NOT NULL,
                  evidence_directory TEXT NOT NULL,
                  created_at TEXT NOT NULL
                );
                CREATE TABLE evidence_stage (
                  stage TEXT PRIMARY KEY,
                  status TEXT NOT NULL,
                  evidence_id TEXT NOT NULL UNIQUE,
                  evidence_path TEXT NOT NULL UNIQUE,
                  evidence_sha256 TEXT NOT NULL,
                  recorded_at TEXT NOT NULL,
                  document_json TEXT NOT NULL,
                  details_json TEXT NOT NULL
                );
                """
                )
                connection.execute(
                    """
                INSERT INTO evidence_run VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                    (
                        run.run_id,
                        run.runner_id,
                        run.release_delivery_plan_id,
                        str(run.platformctl_executable),
                        str(run.local_control_descriptor),
                        str(run.sysctl_executable),
                        str(run.contract_root),
                        str(run.evidence_directory),
                        run.created_at,
                    ),
                )
        return cls(path)

    def load_run(self) -> EvidenceRun:
        with closing(self.open()) as connection:
            row = connection.execute(
                "SELECT * FROM evidence_run WHERE singleton = 1"
            ).fetchone()
        if row is None:
            raise GuestInstalledRuntimeEvidenceError("C78 journal has no run")
        run = EvidenceRun(
            run_id=row["run_id"],
            runner_id=row["runner_id"],
            release_delivery_plan_id=row["release_delivery_plan_id"],
            platformctl_executable=Path(row["platformctl_executable"]),
            local_control_descriptor=Path(row["local_control_descriptor"]),
            sysctl_executable=Path(row["sysctl_executable"]),
            contract_root=Path(row["contract_root"]),
            evidence_directory=Path(row["evidence_directory"]),
            created_at=row["created_at"],
        )
        validate_run(run)
        return run

    def load_stage_document(self, stage: str) -> Mapping[str, Any]:
        validate_stage(stage)
        with closing(self.open()) as connection:
            row = connection.execute(
                "SELECT document_json FROM evidence_stage WHERE stage = ?",
                (stage,),
            ).fetchone()
        if row is None:
            raise GuestInstalledRuntimeEvidenceError(
                "C78 predecessor stage is not recorded: " + stage
            )
        try:
            document = json.loads(row["document_json"])
        except json.JSONDecodeError as error:
            raise GuestInstalledRuntimeEvidenceError(
                "C78 predecessor document is unreadable"
            ) from error
        if not isinstance(document, dict):
            raise GuestInstalledRuntimeEvidenceError(
                "C78 predecessor document is not an object"
            )
        return document

    def record(
        self,
        record: StageRecord,
        document: Mapping[str, Any],
        details: Mapping[str, Any],
    ) -> None:
        validate_stage(record.stage)
        with closing(self.open()) as connection:
            try:
                with connection:
                    connection.execute(
                        """
                    INSERT INTO evidence_stage (
                      stage, status, evidence_id, evidence_path,
                      evidence_sha256, recorded_at, document_json, details_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                        (
                            record.stage,
                            record.status,
                            record.evidence_id,
                            str(record.evidence_path),
                            record.evidence_sha256,
                            record.recorded_at,
                            canonical_json(document),
                            canonical_json(details),
                        ),
                    )
            except sqlite3.IntegrityError as error:
                raise GuestInstalledRuntimeEvidenceError(
                    "C78 stage was already recorded: " + record.stage
                ) from error

    def open(self) -> sqlite3.Connection:
        if not self.path.is_absolute() or not self.path.is_file():
            raise GuestInstalledRuntimeEvidenceError(
                "C78 journal is missing or not an absolute file"
            )
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        return connection


class Runner:
    def __init__(self, journal: Journal):
        self.journal = journal

    def record_first_boot(self) -> StageRecord:
        run = self.journal.load_run()
        return self.observe_and_record(run, FIRST_BOOT_STAGE, None)

    def record_post_reboot(self) -> StageRecord:
        run = self.journal.load_run()
        checkpoint = self.journal.load_stage_document(FIRST_BOOT_STAGE)
        if checkpoint.get("status") != "verified":
            raise GuestInstalledRuntimeEvidenceError(
                "C78 post-reboot evidence requires a verified first-boot checkpoint"
            )
        direct_upload = self.journal.load_stage_document(DIRECT_UPLOAD_STAGE)
        if direct_upload.get("status") != "verified":
            raise GuestInstalledRuntimeEvidenceError(
                "C78 post-reboot evidence requires verified direct-upload lineage"
            )
        return self.observe_and_record(
            run,
            POST_REBOOT_STAGE,
            checkpoint,
            direct_upload["evidenceId"],
        )

    def record_direct_upload(
        self,
        source_vital_file: Path,
        edge_endpoint: str,
        recorder_id: str,
        reported_bed_name: str,
        declared_recorder_code: str,
        upload_id: str,
        curl_executable: Path,
    ) -> StageRecord:
        run = self.journal.load_run()
        checkpoint = self.journal.load_stage_document(FIRST_BOOT_STAGE)
        if checkpoint.get("status") != "verified":
            raise GuestInstalledRuntimeEvidenceError(
                "C78 direct upload requires a verified first-boot checkpoint"
            )
        inputs = validate_direct_upload_inputs(
            source_vital_file,
            edge_endpoint,
            recorder_id,
            reported_bed_name,
            declared_recorder_code,
            upload_id,
            curl_executable,
        )
        recorded_at = utc_timestamp()
        observation, details, observed_issue = observe_direct_upload(
            run,
            inputs,
            recorded_at,
        )
        evidence_id = run.run_id + "-" + DIRECT_UPLOAD_STAGE
        document: dict[str, Any] = {
            "schemaVersion": "v1",
            "evidenceId": evidence_id,
            "releaseDeliveryPlanId": run.release_delivery_plan_id,
            "stage": DIRECT_UPLOAD_STAGE,
            "status": "verified" if observed_issue is None else "failed",
            "recordedAt": recorded_at,
            "runner": {"kind": "guest-installed-runtime", "id": run.runner_id},
            "checkpointEvidenceId": checkpoint["evidenceId"],
        }
        if observed_issue is None:
            document.update(observation)
        else:
            document["issue"] = observed_issue
        return self.publish_stage(run, document, details)

    def observe_and_record(
        self,
        run: EvidenceRun,
        stage: str,
        checkpoint: Mapping[str, Any] | None,
        direct_upload_evidence_id: str | None = None,
    ) -> StageRecord:
        recorded_at = utc_timestamp()
        observation, details, issue = observe_installed_guest(run)
        if issue is None and checkpoint is not None:
            issue = post_reboot_issue(checkpoint, observation)
        evidence_id = run.run_id + "-" + stage
        document: dict[str, Any] = {
            "schemaVersion": "v1",
            "evidenceId": evidence_id,
            "releaseDeliveryPlanId": run.release_delivery_plan_id,
            "stage": stage,
            "status": "verified" if issue is None else "failed",
            "recordedAt": recorded_at,
            "runner": {"kind": "guest-installed-runtime", "id": run.runner_id},
        }
        if checkpoint is not None:
            document["checkpointEvidenceId"] = checkpoint["evidenceId"]
        if direct_upload_evidence_id is not None:
            document["directUploadEvidenceId"] = direct_upload_evidence_id
        if issue is None:
            document.update(observation)
        else:
            document["issue"] = issue
        return self.publish_stage(run, document, details)

    def publish_stage(
        self,
        run: EvidenceRun,
        document: Mapping[str, Any],
        details: Mapping[str, Any],
    ) -> StageRecord:
        validate_evidence_document(run.contract_root, document)
        stage = str(document["stage"])
        recorded_at = str(document["recordedAt"])
        evidence_id = str(document["evidenceId"])
        evidence_path = run.evidence_directory / (stage + ".json")
        payload = (canonical_json(document) + "\n").encode("utf-8")
        write_new_file_atomically(evidence_path, payload)
        record = StageRecord(
            stage=stage,
            status=document["status"],
            evidence_id=evidence_id,
            evidence_path=evidence_path,
            evidence_sha256=hashlib.sha256(payload).hexdigest(),
            recorded_at=recorded_at,
        )
        try:
            self.journal.record(record, document, details)
        except Exception:
            try:
                evidence_path.unlink()
            except OSError as cleanup_error:
                raise GuestInstalledRuntimeEvidenceError(
                    "C78 journal commit failed and the unpublished evidence "
                    "file could not be removed: " + str(cleanup_error)
                )
            raise
        return record


def validate_direct_upload_inputs(
    source_vital_file: Path,
    edge_endpoint: str,
    recorder_id: str,
    reported_bed_name: str,
    declared_recorder_code: str,
    upload_id: str,
    curl_executable: Path,
) -> DirectUploadInputs:
    if (
        not source_vital_file.is_absolute()
        or source_vital_file.is_symlink()
        or not source_vital_file.is_file()
        or source_vital_file.suffix != ".vital"
    ):
        raise GuestInstalledRuntimeEvidenceError(
            "C78 source must be an absolute, non-symlink .vital regular file"
        )
    byte_size = source_vital_file.stat().st_size
    if byte_size < 1:
        raise GuestInstalledRuntimeEvidenceError(
            "C78 source .vital file must not be empty"
        )
    if (
        not curl_executable.is_absolute()
        or curl_executable.is_symlink()
        or not curl_executable.is_file()
        or not os.access(curl_executable, os.X_OK)
    ):
        raise GuestInstalledRuntimeEvidenceError(
            "C78 curl must be an absolute executable regular file"
        )
    parsed_endpoint = urlparse(edge_endpoint)
    if (
        parsed_endpoint.scheme not in {"http", "https"}
        or parsed_endpoint.hostname is None
        or parsed_endpoint.username is not None
        or parsed_endpoint.password is not None
        or parsed_endpoint.query
        or parsed_endpoint.fragment
        or parsed_endpoint.path not in {"", "/"}
    ):
        raise GuestInstalledRuntimeEvidenceError(
            "C78 Edge endpoint must be an explicit HTTP(S) origin without "
            "userinfo, query, fragment, or a non-root path"
        )
    for label, value in (
        ("Recorder ID", recorder_id),
        ("upload ID", upload_id),
    ):
        if not IDENTIFIER_PATTERN.fullmatch(value):
            raise GuestInstalledRuntimeEvidenceError(
                "C78 " + label + " must be a published v1 identifier"
            )
    for label, value in (
        ("reported bed name", reported_bed_name),
        ("declared Recorder code", declared_recorder_code),
    ):
        if (
            not value
            or len(value.encode("utf-8")) > 255
            or "\x00" in value
            or "\r" in value
            or "\n" in value
        ):
            raise GuestInstalledRuntimeEvidenceError(
                "C78 " + label + " must be one bounded non-empty line"
            )
    return DirectUploadInputs(
        source_vital_file=source_vital_file,
        edge_endpoint=edge_endpoint.rstrip("/"),
        recorder_id=recorder_id,
        reported_bed_name=reported_bed_name,
        declared_recorder_code=declared_recorder_code,
        upload_id=upload_id,
        curl_executable=curl_executable,
        byte_size=byte_size,
        sha256=sha256_file(source_vital_file),
    )


def observe_direct_upload(
    run: EvidenceRun,
    inputs: DirectUploadInputs,
    observed_at: str,
) -> tuple[dict[str, Any], dict[str, Any], Mapping[str, Any] | None]:
    assignment_request_id, assignment_evidence_id = direct_upload_assignment_ids(
        run.run_id
    )
    assignment = execute_platformctl(
        run,
        (
            "recorder",
            "assignment",
            "--request-id",
            assignment_request_id,
            "--evidence-id",
            assignment_evidence_id,
            "--recorder-id",
            inputs.recorder_id,
            "--bed-name",
            inputs.reported_bed_name,
            "--effective-from",
            observed_at,
            "--observed-at",
            observed_at,
            "--source-reference-kind",
            "release-evidence-run",
            "--source-reference-id",
            run.run_id,
        ),
    )
    details: dict[str, Any] = {
        "sourceVitalFile": {
            "path": str(inputs.source_vital_file),
            "byteSize": inputs.byte_size,
            "sha256": inputs.sha256,
        },
        "assignment": command_document(assignment),
    }
    assignment_receipt, observed_issue = command_receipt(
        run.contract_root,
        assignment,
        202,
        "recorder-assignment-evidence-receipt.schema.json",
        "recorder-assignment",
    )
    if observed_issue is not None:
        return {}, details, observed_issue
    if (
        assignment_receipt.get("requestId") != assignment_request_id
        or assignment_receipt.get("outcome") not in {"accepted", "duplicate"}
        or assignment_receipt.get("evidenceReference")
        != {
            "kind": "recorder-assignment-evidence",
            "id": assignment_evidence_id,
        }
    ):
        return {}, details, issue(
            "recorder-assignment-receipt-mismatch",
            "Recorder Assignment owner receipt does not match the explicit C78 command.",
            "recorder-assignment-owner",
        )

    upload = execute_upload_command(inputs)
    details["upload"] = command_document(upload)
    if upload.returncode != 0 or upload.stdout != "success":
        return {}, details, issue(
            "recorder-direct-upload-failed",
            "Recorder Gateway did not return the exact successful direct-upload response.",
            "recorder-gateway-upload",
        )

    artifact_page_read = execute_platformctl(
        run,
        (
            "recorder",
            "artifacts",
            "--recorder-id",
            inputs.recorder_id,
            "--limit",
            "100",
        ),
    )
    details["recorderArtifacts"] = command_document(artifact_page_read)
    page, observed_issue = available_contract_value(
        run.contract_root,
        artifact_page_read,
        "recorder-artifact-page.schema.json",
        "recorder-artifact-page",
    )
    if observed_issue is not None:
        return {}, details, observed_issue
    source_receipt_id = "recorder-vital-upload-" + inputs.upload_id
    matching = [
        item
        for item in page["items"]
        if artifact_matches_direct_upload(
            item,
            inputs,
            source_receipt_id,
            assignment_evidence_id,
        )
    ]
    if len(matching) != 1:
        return {}, details, issue(
            "recorder-direct-upload-lineage-not-unique",
            "Archive owner did not expose exactly one matching Recorder-attributed artifact.",
            "archive-export",
        )
    page_detail = matching[0]
    artifact_id = page_detail["artifact"]["artifactId"]
    artifact_read = execute_platformctl(
        run,
        ("archive", "artifact", "--artifact-id", artifact_id),
    )
    details["archiveArtifact"] = command_document(artifact_read)
    artifact_detail, observed_issue = available_contract_value(
        run.contract_root,
        artifact_read,
        "archive-artifact-detail.schema.json",
        "archive-artifact-detail",
    )
    if observed_issue is not None:
        return {}, details, observed_issue
    if artifact_detail != page_detail:
        return {}, details, issue(
            "archive-artifact-owner-reads-disagree",
            "Recorder artifact page and Archive artifact detail returned different owner facts.",
            "archive-export",
        )
    return {
        "edgeEndpoint": inputs.edge_endpoint,
        "sourceVitalFile": {
            "fileName": inputs.source_vital_file.name,
            "byteSize": inputs.byte_size,
            "sha256": inputs.sha256,
        },
        "uploadId": inputs.upload_id,
        "recorderId": inputs.recorder_id,
        "reportedBedName": inputs.reported_bed_name,
        "declaredRecorderCode": inputs.declared_recorder_code,
        "assignmentReceipt": assignment_receipt,
        "artifact": artifact_detail,
    }, details, None


def direct_upload_assignment_ids(run_id: str) -> tuple[str, str]:
    digest = hashlib.sha256(
        (run_id + ":" + DIRECT_UPLOAD_STAGE).encode("utf-8")
    ).hexdigest()[:32]
    return (
        "c78-assignment-request-" + digest,
        "c78-assignment-evidence-" + digest,
    )


def artifact_matches_direct_upload(
    detail: Mapping[str, Any],
    inputs: DirectUploadInputs,
    source_receipt_id: str,
    assignment_evidence_id: str,
) -> bool:
    artifact = detail.get("artifact")
    attribution = detail.get("attribution")
    if not isinstance(artifact, dict) or not isinstance(attribution, dict):
        return False
    manifest = artifact.get("manifest")
    if not isinstance(manifest, dict):
        return False
    manifest_artifact = manifest.get("artifact")
    manifest_source = manifest.get("source")
    if not isinstance(manifest_artifact, dict) or not isinstance(
        manifest_source, dict
    ):
        return False
    return (
        artifact.get("sourceKind") == "recorder-upload"
        and artifact.get("sourceReceiptType") == RECORDER_UPLOAD_RECEIPT_TYPE
        and artifact.get("sourceReceiptId") == source_receipt_id
        and artifact.get("originalFileName") == inputs.source_vital_file.name
        and artifact.get("mediaType") == "application/x-vital"
        and artifact.get("byteSize") == inputs.byte_size
        and artifact.get("sha256") == inputs.sha256
        and artifact.get("finalizationState") == "finalized"
        and manifest_source.get("kind") == "recorder-upload"
        and manifest_source.get("receiptType") == RECORDER_UPLOAD_RECEIPT_TYPE
        and manifest_source.get("receiptId") == source_receipt_id
        and manifest_artifact.get("artifactId") == artifact.get("artifactId")
        and manifest_artifact.get("byteSize") == inputs.byte_size
        and manifest_artifact.get("sha256") == inputs.sha256
        and attribution.get("reportedBedName") == inputs.reported_bed_name
        and attribution.get("outcome") == "matched"
        and attribution.get("matchedRecorderId") == inputs.recorder_id
        and attribution.get("candidateRecorderIds") == [inputs.recorder_id]
        and attribution.get("assignmentEvidenceReference")
        == {
            "kind": "recorder-assignment-evidence",
            "id": assignment_evidence_id,
        }
    )


def observe_installed_guest(
    run: EvidenceRun,
) -> tuple[dict[str, Any], dict[str, Any], Mapping[str, Any] | None]:
    boot_before = execute_command(run.sysctl_executable, ("-n", "kern.bootsessionuuid"))
    readiness = execute_platformctl(run, ("runtime", "readiness"))
    identity = execute_platformctl(
        run, ("runtime", "operational-state-identity")
    )
    boot_after = execute_command(run.sysctl_executable, ("-n", "kern.bootsessionuuid"))
    details = {
        "bootSessionBefore": command_document(boot_before),
        "readiness": command_document(readiness),
        "identity": command_document(identity),
        "bootSessionAfter": command_document(boot_after),
    }
    boot_before_id, boot_issue = boot_session(boot_before)
    if boot_issue is not None:
        return {}, details, boot_issue
    boot_after_id, boot_issue = boot_session(boot_after)
    if boot_issue is not None:
        return {}, details, boot_issue
    if boot_before_id != boot_after_id:
        return {}, details, issue(
            "host-reboot-during-guest-observation",
            "The Host boot session changed while C78 observed Guest readiness and identity.",
            "macos-host-boot-session",
        )
    readiness_document, read_issue = available_read_result(
        readiness, "guest-runtime-readiness"
    )
    if read_issue is not None:
        return {}, details, read_issue
    readiness_value = readiness_document["value"]
    if (
        readiness_value.get("schemaVersion") != "v1"
        or readiness_value.get("state") != "ready"
        or not isinstance(readiness_value.get("observedAt"), str)
    ):
        return {}, details, issue(
            "guest-runtime-readiness-not-ready",
            "The Guest Runtime readiness owner did not report ready.",
            "guest-runtime-readiness",
        )
    identity_document, read_issue = available_read_result(
        identity, "guest-operational-state-identity"
    )
    if read_issue is not None:
        return {}, details, read_issue
    try:
        validate_identity(run.contract_root, identity_document["value"])
    except GuestInstalledRuntimeEvidenceError as error:
        return {}, details, issue(
            "guest-operational-state-identity-contract-invalid",
            str(error),
            "guest-operational-state-identity",
        )
    return {
        "hostBootSessionIdentifier": boot_before_id,
        "readinessObservedAt": readiness_value["observedAt"],
        "identity": identity_document["value"],
    }, details, None


def post_reboot_issue(
    checkpoint: Mapping[str, Any],
    current: Mapping[str, Any],
) -> Mapping[str, Any] | None:
    if (
        current["hostBootSessionIdentifier"]
        == checkpoint["hostBootSessionIdentifier"]
    ):
        return issue(
            "host-reboot-not-observed",
            "The Host boot-session identifier did not change after the first-boot checkpoint.",
            "macos-host-boot-session",
        )
    before = checkpoint["identity"]
    after = current["identity"]
    for owner in ("sqlite", "postgresql", "bootstrap"):
        if before.get(owner) != after.get(owner):
            return issue(
                "guest-operational-state-identity-changed-after-reboot",
                "The Guest " + owner + " owner identity changed after the observed Host reboot.",
                "guest-operational-state-identity",
            )
    return None


def execute_platformctl(
    run: EvidenceRun, arguments: tuple[str, ...]
) -> CommandObservation:
    return execute_command(
        run.platformctl_executable,
        (
            "--local-control-descriptor",
            str(run.local_control_descriptor),
            *arguments,
        ),
    )


def execute_upload_command(inputs: DirectUploadInputs) -> CommandObservation:
    return execute_command(
        inputs.curl_executable,
        (
            "--fail-with-body",
            "--silent",
            "--show-error",
            "--max-time",
            "300",
            "--request",
            "POST",
            "--header",
            "x-vital-upload-id: " + inputs.upload_id,
            "--form-string",
            "bedname=" + inputs.reported_bed_name,
            "--form-string",
            "vrcode=" + inputs.declared_recorder_code,
            "--form",
            "vitalfile=@"
            + str(inputs.source_vital_file)
            + ";type=application/x-vital",
            inputs.edge_endpoint + "/upload",
        ),
        timeout_seconds=330,
    )


def execute_command(
    executable: Path,
    arguments: tuple[str, ...],
    timeout_seconds: int = 30,
) -> CommandObservation:
    completed = subprocess.run(
        [str(executable), *arguments],
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout_seconds,
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
    )
    return CommandObservation(
        executable=executable,
        arguments=arguments,
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def boot_session(
    observation: CommandObservation,
) -> tuple[str, Mapping[str, Any] | None]:
    value = observation.stdout.strip()
    if observation.returncode != 0 or not value or "\n" in value or len(value) > 256:
        return "", issue(
            "host-boot-session-observation-failed",
            "sysctl did not return one bounded Host boot-session identifier.",
            "macos-host-boot-session",
        )
    return value, None


def available_read_result(
    observation: CommandObservation,
    dependency: str,
) -> tuple[Mapping[str, Any], Mapping[str, Any] | None]:
    if observation.returncode != 0:
        return {}, issue(
            dependency + "-read-failed",
            "platformctl did not return a successful local-control response.",
            dependency,
        )
    try:
        envelope = json.loads(observation.stdout)
    except json.JSONDecodeError:
        return {}, issue(
            dependency + "-response-invalid",
            "platformctl output is not one JSON document.",
            dependency,
        )
    if (
        not isinstance(envelope, dict)
        or envelope.get("httpStatus") != 200
        or not isinstance(envelope.get("document"), dict)
    ):
        return {}, issue(
            dependency + "-response-invalid",
            "platformctl did not return HTTP 200 with one owner document.",
            dependency,
        )
    document = envelope["document"]
    if (
        document.get("schemaVersion") != "v1"
        or document.get("state") != "available"
        or not isinstance(document.get("observedAt"), str)
        or not isinstance(document.get("value"), dict)
    ):
        return {}, issue(
            dependency + "-not-available",
            "The owner read is not explicitly available with a value.",
            dependency,
        )
    return document, None


def command_receipt(
    contract_root: Path,
    observation: CommandObservation,
    expected_http_status: int,
    schema_file_name: str,
    dependency: str,
) -> tuple[Mapping[str, Any], Mapping[str, Any] | None]:
    if observation.returncode != 0:
        return {}, issue(
            dependency + "-command-failed",
            "platformctl did not return a successful local-control response.",
            dependency,
        )
    try:
        envelope = json.loads(observation.stdout)
    except json.JSONDecodeError:
        return {}, issue(
            dependency + "-response-invalid",
            "platformctl output is not one JSON document.",
            dependency,
        )
    if (
        not isinstance(envelope, dict)
        or envelope.get("httpStatus") != expected_http_status
        or not isinstance(envelope.get("document"), dict)
    ):
        return {}, issue(
            dependency + "-response-invalid",
            "platformctl did not return the expected HTTP status with one owner document.",
            dependency,
        )
    document = envelope["document"]
    findings = validate_contract_instance(
        contract_root,
        schema_file_name,
        document,
    )
    if findings:
        return {}, issue(
            dependency + "-contract-invalid",
            "Owner response failed its published contract: " + findings,
            dependency,
        )
    return document, None


def available_contract_value(
    contract_root: Path,
    observation: CommandObservation,
    schema_file_name: str,
    dependency: str,
) -> tuple[Mapping[str, Any], Mapping[str, Any] | None]:
    read_result, observed_issue = available_read_result(observation, dependency)
    if observed_issue is not None:
        return {}, observed_issue
    value = read_result["value"]
    findings = validate_contract_instance(
        contract_root,
        schema_file_name,
        value,
    )
    if findings:
        return {}, issue(
            dependency + "-contract-invalid",
            "Owner value failed its published contract: " + findings,
            dependency,
        )
    return value, None


def validate_contract_instance(
    contract_root: Path,
    schema_file_name: str,
    document: Mapping[str, Any],
) -> str:
    repository = ContractRepository(contract_root)
    repository.load()
    findings = repository.validate_instance(schema_file_name, document)
    return "; ".join(item.render() for item in findings)


def validate_identity(contract_root: Path, identity: Mapping[str, Any]) -> None:
    findings = validate_contract_instance(
        contract_root,
        "guest-operational-state-identity.schema.json",
        identity,
    )
    if findings:
        raise GuestInstalledRuntimeEvidenceError(
            "C77 validation failed: " + findings
        )


def validate_evidence_document(
    contract_root: Path, document: Mapping[str, Any]
) -> None:
    repository = ContractRepository(contract_root)
    repository.load()
    findings = repository.validate_instance(
        "guest-installed-runtime-evidence.schema.json", document
    )
    if findings:
        raise GuestInstalledRuntimeEvidenceError(
            "C78 validation failed: " + "; ".join(item.render() for item in findings)
        )


def validate_run(run: EvidenceRun) -> None:
    for label, value in (
        ("run ID", run.run_id),
        ("runner ID", run.runner_id),
        ("release delivery plan ID", run.release_delivery_plan_id),
    ):
        if not isinstance(value, str) or not IDENTIFIER_PATTERN.fullmatch(value):
            raise GuestInstalledRuntimeEvidenceError(
                "C78 " + label + " must be a published v1 identifier"
            )
    for stage in STAGES:
        if not IDENTIFIER_PATTERN.fullmatch(run.run_id + "-" + stage):
            raise GuestInstalledRuntimeEvidenceError(
                "C78 run ID is too long for its immutable stage evidence IDs"
            )
    for label, path in (
        ("platformctl executable", run.platformctl_executable),
        ("sysctl executable", run.sysctl_executable),
    ):
        if not path.is_absolute() or path.is_symlink() or not path.is_file() or not os.access(path, os.X_OK):
            raise GuestInstalledRuntimeEvidenceError(
                "C78 " + label + " must be an absolute executable regular file"
            )
    if (
        not run.local_control_descriptor.is_absolute()
        or run.local_control_descriptor.is_symlink()
        or not run.local_control_descriptor.is_file()
    ):
        raise GuestInstalledRuntimeEvidenceError(
            "C78 local-control descriptor must be an absolute regular file"
        )
    if (
        not run.contract_root.is_absolute()
        or not (run.contract_root / "contracts" / "catalog" / "v1.json").is_file()
    ):
        raise GuestInstalledRuntimeEvidenceError(
            "C78 contract root must contain the canonical contract repository"
        )
    if not run.evidence_directory.is_absolute() or not run.evidence_directory.is_dir():
        raise GuestInstalledRuntimeEvidenceError(
            "C78 evidence directory must be an existing absolute directory"
        )


def validate_stage(stage: str) -> None:
    if stage not in STAGES:
        raise GuestInstalledRuntimeEvidenceError("unknown C78 stage: " + stage)


def issue(code: str, message: str, dependency: str) -> Mapping[str, Any]:
    return {
        "code": code,
        "message": message,
        "retryable": False,
        "dependency": dependency,
    }


def command_document(observation: CommandObservation) -> Mapping[str, Any]:
    return {
        "executable": str(observation.executable),
        "arguments": list(observation.arguments),
        "returnCode": observation.returncode,
        "stdout": observation.stdout,
        "stderr": observation.stderr,
    }


def write_new_file_atomically(path: Path, payload: bytes) -> None:
    if not path.is_absolute() or not path.parent.is_dir() or path.exists():
        raise GuestInstalledRuntimeEvidenceError(
            "C78 evidence output must be a new absolute path"
        )
    descriptor, temporary_name = tempfile.mkstemp(
        prefix="." + path.name + ".",
        dir=path.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(payload)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def canonical_json(document: Mapping[str, Any]) -> str:
    return json.dumps(document, sort_keys=True, separators=(",", ":"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create-run")
    create.add_argument("--journal", type=Path, required=True)
    create.add_argument("--run-id", required=True)
    create.add_argument("--runner-id", required=True)
    create.add_argument("--release-delivery-plan-id", required=True)
    create.add_argument("--platformctl", type=Path, required=True)
    create.add_argument("--local-control-descriptor", type=Path, required=True)
    create.add_argument("--sysctl", type=Path, default=Path("/usr/sbin/sysctl"))
    create.add_argument("--contract-root", type=Path, required=True)
    create.add_argument("--evidence-directory", type=Path, required=True)
    for name in ("record-first-boot", "record-post-reboot"):
        command = commands.add_parser(name)
        command.add_argument("--journal", type=Path, required=True)
    upload = commands.add_parser("record-direct-upload")
    upload.add_argument("--journal", type=Path, required=True)
    upload.add_argument("--source-vital-file", type=Path, required=True)
    upload.add_argument("--edge-endpoint", required=True)
    upload.add_argument("--recorder-id", required=True)
    upload.add_argument("--reported-bed-name", required=True)
    upload.add_argument("--declared-recorder-code", required=True)
    upload.add_argument("--upload-id", required=True)
    upload.add_argument("--curl", type=Path, default=Path("/usr/bin/curl"))
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(arguments if arguments is not None else os.sys.argv[1:])
    if options.command == "create-run":
        run = EvidenceRun(
            run_id=options.run_id,
            runner_id=options.runner_id,
            release_delivery_plan_id=options.release_delivery_plan_id,
            platformctl_executable=options.platformctl.resolve(),
            local_control_descriptor=options.local_control_descriptor.resolve(),
            sysctl_executable=options.sysctl.resolve(),
            contract_root=options.contract_root.resolve(),
            evidence_directory=options.evidence_directory.resolve(),
            created_at=utc_timestamp(),
        )
        Journal.create(options.journal.resolve(), run)
        print(canonical_json({"state": "created", "runId": run.run_id}))
        return 0
    runner = Runner(Journal(options.journal.resolve()))
    if options.command == "record-first-boot":
        record = runner.record_first_boot()
    elif options.command == "record-direct-upload":
        record = runner.record_direct_upload(
            options.source_vital_file.resolve(),
            options.edge_endpoint,
            options.recorder_id,
            options.reported_bed_name,
            options.declared_recorder_code,
            options.upload_id,
            options.curl.resolve(),
        )
    else:
        record = runner.record_post_reboot()
    print(
        canonical_json(
            {
                "stage": record.stage,
                "status": record.status,
                "evidencePath": str(record.evidence_path),
                "evidenceSHA256": record.evidence_sha256,
            }
        )
    )
    return 0 if record.status == "verified" else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GuestInstalledRuntimeEvidenceError as error:
        print("guest-installed-runtime-evidence:", error, file=os.sys.stderr)
        raise SystemExit(2)
