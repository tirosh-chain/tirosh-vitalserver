#!/usr/bin/env python3
"""Collect explicit macOS clean-Host C24 release-delivery evidence.

This Release-process tool owns only one ``MacOSCleanHostReleaseEvidenceRun``
and its SQLite journal.  It does not own Host Agent, Guest Runtime, launchd,
or installer state.  Those facts are observed through explicitly configured
macOS command-line contracts and then written as evidence documents plus C24
proof fragments.

The runner intentionally separates these operations:

* artifact integrity observes the selected signed PKG;
* clean-Host preflight observes that the C23 receipt and launchd registrations
  are absent before installation;
* clean installation performs ``installer`` only with an explicit CLI grant;
* service registration observes each C23-named launchd service after install;
* reboot uses a durable boot-session checkpoint and never reboots a Host by
  itself.

Missing commands, ambiguous command output, a changed artifact, an existing
receipt, and a missing service remain explicit failures.  None become a clean
Host, a registered service, or a verified C24 proof by fallback.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import sqlite3
import subprocess
import sys
import tempfile
from typing import Any, Mapping, Sequence
import xml.etree.ElementTree as ElementTree

from tooling.product_delivery_release_plan import (
    MacOSHostPackageReleasePlan,
    ProductDeliveryReleasePlanError,
    load_selected_macos_host_package_release_plan,
)


class MacOSCleanHostReleaseEvidenceRunError(RuntimeError):
    """A clean-Host release evidence fact is unavailable, invalid, or unsafe."""


ARTIFACT_INTEGRITY_STAGE = "artifact-integrity"
CLEAN_HOST_PREFLIGHT_STAGE = "clean-host-preflight"
CLEAN_INSTALL_STAGE = "clean-install"
SERVICE_REGISTRATION_STAGE = "service-registration"
REBOOT_CHECKPOINT_STAGE = "reboot-checkpoint"
REBOOT_STAGE = "reboot"

RELEASE_EVIDENCE_STAGES = {
    ARTIFACT_INTEGRITY_STAGE,
    CLEAN_HOST_PREFLIGHT_STAGE,
    CLEAN_INSTALL_STAGE,
    SERVICE_REGISTRATION_STAGE,
    REBOOT_CHECKPOINT_STAGE,
    REBOOT_STAGE,
}

EXPLICITLY_ABSENT_PACKAGE_RECEIPT_MARKERS = (
    "no receipt for",
    "no receipt found",
)
EXPLICITLY_ABSENT_LAUNCHD_SERVICE_MARKERS = (
    "could not find service",
    "service not found",
)


@dataclass(frozen=True)
class MacOSCleanHostReleaseEvidenceCommandContract:
    """Explicit macOS command executables through which this run observes facts."""

    pkgutil_executable: Path
    installer_executable: Path
    launchctl_executable: Path
    sysctl_executable: Path


@dataclass(frozen=True)
class MacOSCleanHostReleaseEvidenceRun:
    """Release-process-owned durable identity for one clean-Host evidence run."""

    run_id: str
    runner_id: str
    release_delivery_plan_id: str
    product_version: str
    intended_installer_file_name: str
    macos_installer_package_identifier: str
    host_agent_launchd_service_label: str
    host_edge_proxy_launchd_service_label: str
    installer_artifact_path: Path
    bound_installer_artifact_sha256: str
    evidence_directory: Path
    command_contract: MacOSCleanHostReleaseEvidenceCommandContract
    created_at: str


@dataclass(frozen=True)
class MacOSCleanHostReleaseEvidenceCommandObservation:
    """Exact external-command evidence; no return-code interpretation is hidden."""

    executable: Path
    arguments: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class MacOSPackageReceiptObservation:
    """A pkgutil observation of one C23 macOS installer receipt."""

    state: str
    package_identifier: str | None
    product_version: str | None
    command: MacOSCleanHostReleaseEvidenceCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class MacOSInstallerArtifactReleaseIdentityObservation:
    """An expanded flat-PKG observation of the selected release identity."""

    state: str
    package_identifier: str | None
    product_version: str | None
    package_expansion_command: MacOSCleanHostReleaseEvidenceCommandObservation
    reason: str | None = None


@dataclass(frozen=True)
class MacOSLaunchdServiceRegistrationObservation:
    """A launchctl observation of one C23-required Host service registration."""

    role: str
    service_label: str
    state: str
    command: MacOSCleanHostReleaseEvidenceCommandObservation


@dataclass(frozen=True)
class MacOSHostBootSessionObservation:
    """A sysctl observation of the macOS boot session boundary."""

    boot_session_identifier: str
    command: MacOSCleanHostReleaseEvidenceCommandObservation


@dataclass(frozen=True)
class MacOSCleanHostReleaseEvidenceStageRecord:
    """The journal's immutable result for one evidence collection attempt."""

    stage: str
    status: str
    recorded_at: str
    evidence_path: Path
    evidence_sha256: str
    c24_proof: Mapping[str, Any] | None


class MacOSCleanHostReleaseEvidenceJournal:
    """SQLite owner for one clean-Host release evidence run and its stages.

    This journal is a release-tool boundary.  It deliberately does not reuse
    Host Agent's SQLite database: C24 collection state and Host lifecycle state
    have different owners, transition rules, and retention purposes.
    """

    def __init__(self, journal_path: Path):
        self.journal_path = journal_path

    @classmethod
    def create_new(
        cls,
        journal_path: Path,
        evidence_run: MacOSCleanHostReleaseEvidenceRun,
    ) -> "MacOSCleanHostReleaseEvidenceJournal":
        validate_new_journal_path(journal_path)
        journal = cls(journal_path)
        try:
            with sqlite3.connect(journal_path) as connection:
                connection.executescript(
                    """
                    CREATE TABLE evidence_run (
                        run_id TEXT PRIMARY KEY,
                        runner_id TEXT NOT NULL,
                        release_delivery_plan_id TEXT NOT NULL,
                        product_version TEXT NOT NULL,
                        intended_installer_file_name TEXT NOT NULL,
                        macos_installer_package_identifier TEXT NOT NULL,
                        host_agent_launchd_service_label TEXT NOT NULL,
                        host_edge_proxy_launchd_service_label TEXT NOT NULL,
                        installer_artifact_path TEXT NOT NULL,
                        bound_installer_artifact_sha256 TEXT NOT NULL,
                        evidence_directory TEXT NOT NULL,
                        command_contract_json TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    );
                    CREATE TABLE evidence_stage (
                        stage TEXT PRIMARY KEY,
                        status TEXT NOT NULL,
                        recorded_at TEXT NOT NULL,
                        evidence_path TEXT NOT NULL,
                        evidence_sha256 TEXT NOT NULL,
                        c24_proof_json TEXT,
                        details_json TEXT NOT NULL
                    );
                    """
                )
                connection.execute(
                    """
                    INSERT INTO evidence_run (
                        run_id, runner_id, release_delivery_plan_id,
                        product_version, intended_installer_file_name,
                        macos_installer_package_identifier,
                        host_agent_launchd_service_label,
                        host_edge_proxy_launchd_service_label,
                        installer_artifact_path,
                        bound_installer_artifact_sha256, evidence_directory,
                        command_contract_json, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        evidence_run.run_id,
                        evidence_run.runner_id,
                        evidence_run.release_delivery_plan_id,
                        evidence_run.product_version,
                        evidence_run.intended_installer_file_name,
                        evidence_run.macos_installer_package_identifier,
                        evidence_run.host_agent_launchd_service_label,
                        evidence_run.host_edge_proxy_launchd_service_label,
                        str(evidence_run.installer_artifact_path),
                        evidence_run.bound_installer_artifact_sha256,
                        str(evidence_run.evidence_directory),
                        canonical_json(
                            command_contract_document(
                                evidence_run.command_contract
                            )
                        ),
                        evidence_run.created_at,
                    ),
                )
        except sqlite3.Error as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence journal creation failed: "
                + str(error)
            ) from error
        return journal

    def load_evidence_run(self) -> MacOSCleanHostReleaseEvidenceRun:
        connection = self.open_existing_connection()
        try:
            row = connection.execute("SELECT * FROM evidence_run").fetchone()
        except sqlite3.Error as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence journal read failed: "
                + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence journal has no evidence run"
            )
        try:
            command_contract_document_value = json.loads(
                row["command_contract_json"]
            )
        except (TypeError, json.JSONDecodeError) as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence journal command contract is unreadable"
            ) from error
        command_contract = command_contract_from_journal_document(
            command_contract_document_value
        )
        validate_command_contract(command_contract)
        return MacOSCleanHostReleaseEvidenceRun(
            run_id=required_non_empty_string(row["run_id"], "journal run ID"),
            runner_id=required_non_empty_string(row["runner_id"], "journal runner ID"),
            release_delivery_plan_id=required_non_empty_string(
                row["release_delivery_plan_id"], "journal release delivery plan ID"
            ),
            product_version=required_non_empty_string(
                row["product_version"], "journal product version"
            ),
            intended_installer_file_name=required_non_empty_string(
                row["intended_installer_file_name"], "journal installer file name"
            ),
            macos_installer_package_identifier=required_non_empty_string(
                row["macos_installer_package_identifier"],
                "journal macOS installer package identifier",
            ),
            host_agent_launchd_service_label=required_non_empty_string(
                row["host_agent_launchd_service_label"],
                "journal Host Agent launchd service label",
            ),
            host_edge_proxy_launchd_service_label=required_non_empty_string(
                row["host_edge_proxy_launchd_service_label"],
                "journal Host Edge Proxy launchd service label",
            ),
            installer_artifact_path=Path(
                required_non_empty_string(
                    row["installer_artifact_path"], "journal installer artifact path"
                )
            ),
            bound_installer_artifact_sha256=required_sha256(
                row["bound_installer_artifact_sha256"],
                "journal bound installer artifact SHA-256",
            ),
            evidence_directory=Path(
                required_non_empty_string(
                    row["evidence_directory"], "journal evidence directory"
                )
            ),
            command_contract=command_contract,
            created_at=required_non_empty_string(
                row["created_at"], "journal creation timestamp"
            ),
        )

    def load_stage_record(
        self, stage: str
    ) -> MacOSCleanHostReleaseEvidenceStageRecord | None:
        validate_release_evidence_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT * FROM evidence_stage WHERE stage = ?", (stage,)
            ).fetchone()
        except sqlite3.Error as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage read failed: " + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            return None
        c24_proof_json = row["c24_proof_json"]
        try:
            c24_proof = (
                json.loads(c24_proof_json) if c24_proof_json is not None else None
            )
        except json.JSONDecodeError as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage C24 proof is unreadable"
            ) from error
        if c24_proof is not None and not isinstance(c24_proof, dict):
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage C24 proof must be an object"
            )
        return MacOSCleanHostReleaseEvidenceStageRecord(
            stage=stage,
            status=required_non_empty_string(row["status"], "journal stage status"),
            recorded_at=required_non_empty_string(
                row["recorded_at"], "journal stage timestamp"
            ),
            evidence_path=Path(
                required_non_empty_string(row["evidence_path"], "journal evidence path")
            ),
            evidence_sha256=required_sha256(
                row["evidence_sha256"], "journal evidence SHA-256"
            ),
            c24_proof=c24_proof,
        )

    def record_new_stage(
        self,
        stage_record: MacOSCleanHostReleaseEvidenceStageRecord,
        details: Mapping[str, Any],
    ) -> None:
        validate_release_evidence_stage(stage_record.stage)
        if stage_record.status not in {"verified", "failed"}:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage status must be verified or failed"
            )
        connection = self.open_existing_connection()
        try:
            existing = connection.execute(
                "SELECT stage FROM evidence_stage WHERE stage = ?",
                (stage_record.stage,),
            ).fetchone()
            if existing is not None:
                raise MacOSCleanHostReleaseEvidenceRunError(
                    "macOS clean-Host release evidence stage was already recorded: "
                    + stage_record.stage
                )
            connection.execute(
                """
                INSERT INTO evidence_stage (
                    stage, status, recorded_at, evidence_path, evidence_sha256,
                    c24_proof_json, details_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    stage_record.stage,
                    stage_record.status,
                    stage_record.recorded_at,
                    str(stage_record.evidence_path),
                    stage_record.evidence_sha256,
                    canonical_json(stage_record.c24_proof)
                    if stage_record.c24_proof is not None
                    else None,
                    canonical_json(dict(details)),
                ),
            )
            connection.commit()
        except sqlite3.Error as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage write failed: " + str(error)
            ) from error
        finally:
            connection.close()

    def load_stage_details(self, stage: str) -> Mapping[str, Any]:
        validate_release_evidence_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT details_json FROM evidence_stage WHERE stage = ?", (stage,)
            ).fetchone()
        except sqlite3.Error as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage details read failed: "
                + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage is not recorded: " + stage
            )
        try:
            details = json.loads(row["details_json"])
        except (TypeError, json.JSONDecodeError) as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage details are unreadable"
            ) from error
        if not isinstance(details, dict):
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage details must be an object"
            )
        return details

    def open_existing_connection(self) -> sqlite3.Connection:
        if not self.journal_path.is_absolute() or not self.journal_path.is_file():
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence journal is missing or not a file"
            )
        try:
            connection = sqlite3.connect(self.journal_path)
            connection.row_factory = sqlite3.Row
            return connection
        except sqlite3.Error as error:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence journal cannot be opened: "
                + str(error)
            ) from error


class MacOSCleanHostReleaseEvidenceRunner:
    """Application workflow for explicit macOS clean-Host evidence transitions."""

    def __init__(self, journal: MacOSCleanHostReleaseEvidenceJournal):
        self.journal = journal

    def record_artifact_integrity(self) -> MacOSCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.journal.load_evidence_run()
        observed_at = utc_timestamp()
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        installer_artifact_release_identity = (
            observe_macos_installer_artifact_release_identity(
                evidence_run.command_contract.pkgutil_executable,
                evidence_run.installer_artifact_path,
            )
        )
        package_signature_command = execute_macos_clean_host_command(
            evidence_run.command_contract.pkgutil_executable,
            ["--check-signature", str(evidence_run.installer_artifact_path)],
        )
        issue = evaluate_macos_installer_artifact_integrity_issue(
            evidence_run,
            installer_artifact_release_identity,
            package_signature_command,
        )
        details = {
            "observedInstallerArtifact": observed_artifact,
            "installerArtifactReleaseIdentityObservation": (
                installer_artifact_release_identity_document(
                    installer_artifact_release_identity
                )
            ),
            "packageSignatureCommand": command_document(package_signature_command),
        }
        if issue is None:
            return self.record_stage_with_c24_proof(
                evidence_run,
                ARTIFACT_INTEGRITY_STAGE,
                "verified",
                observed_at,
                details,
                compose_verified_c24_proof(
                    evidence_run,
                    ARTIFACT_INTEGRITY_STAGE,
                    observed_at,
                    observed_artifact,
                ),
            )
        return self.record_stage_with_c24_proof(
            evidence_run,
            ARTIFACT_INTEGRITY_STAGE,
            "failed",
            observed_at,
            details,
            compose_failed_c24_proof(
                evidence_run, ARTIFACT_INTEGRITY_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_clean_host_preflight(self) -> MacOSCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(ARTIFACT_INTEGRITY_STAGE)
        observed_at = utc_timestamp()
        package_receipt = observe_macos_package_receipt(
            evidence_run.command_contract.pkgutil_executable,
            evidence_run.macos_installer_package_identifier,
        )
        service_observations = observe_required_launchd_service_registrations(
            evidence_run.command_contract.launchctl_executable,
            evidence_run,
        )
        issue = clean_host_preflight_issue(package_receipt, service_observations)
        details = {
            "packageReceiptObservation": package_receipt_document(package_receipt),
            "launchdServiceRegistrationObservations": [
                launchd_service_registration_document(observation)
                for observation in service_observations
            ],
        }
        return self.record_stage_with_c24_proof(
            evidence_run,
            CLEAN_HOST_PREFLIGHT_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            None,
            issue,
        )

    def execute_clean_install(self) -> MacOSCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(CLEAN_HOST_PREFLIGHT_STAGE)
        if os.geteuid() != 0:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host package installation requires a root runner process"
            )
        observed_at = utc_timestamp()
        installer_command = execute_macos_clean_host_command(
            evidence_run.command_contract.installer_executable,
            ["-pkg", str(evidence_run.installer_artifact_path), "-target", "/"],
        )
        package_receipt = observe_macos_package_receipt(
            evidence_run.command_contract.pkgutil_executable,
            evidence_run.macos_installer_package_identifier,
        )
        issue = clean_install_issue(evidence_run, installer_command, package_receipt)
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        details = {
            "installerCommand": command_document(installer_command),
            "packageReceiptObservation": package_receipt_document(package_receipt),
            "observedInstallerArtifact": observed_artifact,
        }
        if issue is None:
            proof = compose_verified_c24_proof(
                evidence_run,
                CLEAN_INSTALL_STAGE,
                observed_at,
                observed_artifact,
                observed_macos_installer_receipt(evidence_run, package_receipt, observed_at),
            )
            return self.record_stage_with_c24_proof(
                evidence_run,
                CLEAN_INSTALL_STAGE,
                "verified",
                observed_at,
                details,
                proof,
            )
        return self.record_stage_with_c24_proof(
            evidence_run,
            CLEAN_INSTALL_STAGE,
            "failed",
            observed_at,
            details,
            compose_failed_c24_proof(
                evidence_run, CLEAN_INSTALL_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_service_registration(self) -> MacOSCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(CLEAN_INSTALL_STAGE)
        observed_at = utc_timestamp()
        package_receipt = observe_macos_package_receipt(
            evidence_run.command_contract.pkgutil_executable,
            evidence_run.macos_installer_package_identifier,
        )
        service_observations = observe_required_launchd_service_registrations(
            evidence_run.command_contract.launchctl_executable,
            evidence_run,
        )
        issue = installed_receipt_or_service_registration_issue(
            evidence_run, package_receipt, service_observations
        )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        details = {
            "packageReceiptObservation": package_receipt_document(package_receipt),
            "launchdServiceRegistrationObservations": [
                launchd_service_registration_document(observation)
                for observation in service_observations
            ],
            "observedInstallerArtifact": observed_artifact,
        }
        if issue is None:
            proof = compose_verified_c24_proof(
                evidence_run,
                SERVICE_REGISTRATION_STAGE,
                observed_at,
                observed_artifact,
                observed_host_service_registrations(
                    service_observations, observed_at
                ),
            )
            return self.record_stage_with_c24_proof(
                evidence_run,
                SERVICE_REGISTRATION_STAGE,
                "verified",
                observed_at,
                details,
                proof,
            )
        return self.record_stage_with_c24_proof(
            evidence_run,
            SERVICE_REGISTRATION_STAGE,
            "failed",
            observed_at,
            details,
            compose_failed_c24_proof(
                evidence_run, SERVICE_REGISTRATION_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_reboot_checkpoint(self) -> MacOSCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(SERVICE_REGISTRATION_STAGE)
        observed_at = utc_timestamp()
        boot_session = observe_macos_host_boot_session(
            evidence_run.command_contract.sysctl_executable
        )
        details = {"bootSessionObservation": boot_session_document(boot_session)}
        return self.record_stage_with_c24_proof(
            evidence_run,
            REBOOT_CHECKPOINT_STAGE,
            "verified",
            observed_at,
            details,
            None,
        )

    def record_reboot(self) -> MacOSCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(REBOOT_CHECKPOINT_STAGE)
        checkpoint_details = self.journal.load_stage_details(REBOOT_CHECKPOINT_STAGE)
        checkpoint_session_identifier = boot_session_identifier_from_checkpoint(
            checkpoint_details
        )
        observed_at = utc_timestamp()
        current_boot_session = observe_macos_host_boot_session(
            evidence_run.command_contract.sysctl_executable
        )
        package_receipt = observe_macos_package_receipt(
            evidence_run.command_contract.pkgutil_executable,
            evidence_run.macos_installer_package_identifier,
        )
        service_observations = observe_required_launchd_service_registrations(
            evidence_run.command_contract.launchctl_executable,
            evidence_run,
        )
        issue = reboot_persistence_issue(
            evidence_run,
            checkpoint_session_identifier,
            current_boot_session,
            package_receipt,
            service_observations,
        )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        details = {
            "preRebootBootSessionIdentifier": checkpoint_session_identifier,
            "postRebootBootSessionObservation": boot_session_document(
                current_boot_session
            ),
            "packageReceiptObservation": package_receipt_document(package_receipt),
            "launchdServiceRegistrationObservations": [
                launchd_service_registration_document(observation)
                for observation in service_observations
            ],
            "observedInstallerArtifact": observed_artifact,
        }
        if issue is None:
            return self.record_stage_with_c24_proof(
                evidence_run,
                REBOOT_STAGE,
                "verified",
                observed_at,
                details,
                compose_verified_c24_proof(
                    evidence_run,
                    REBOOT_STAGE,
                    observed_at,
                    observed_artifact,
                ),
            )
        return self.record_stage_with_c24_proof(
            evidence_run,
            REBOOT_STAGE,
            "failed",
            observed_at,
            details,
            compose_failed_c24_proof(
                evidence_run, REBOOT_STAGE, observed_at, issue
            ),
            issue,
        )

    def require_verified_predecessor(
        self, predecessor_stage: str
    ) -> MacOSCleanHostReleaseEvidenceRun:
        evidence_run = self.journal.load_evidence_run()
        predecessor = self.journal.load_stage_record(predecessor_stage)
        if predecessor is None or predecessor.status != "verified":
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence requires verified predecessor stage: "
                + predecessor_stage
            )
        assert_bound_installer_artifact_is_unchanged(evidence_run)
        return evidence_run

    def record_stage_with_c24_proof(
        self,
        evidence_run: MacOSCleanHostReleaseEvidenceRun,
        stage: str,
        status: str,
        recorded_at: str,
        details: Mapping[str, Any],
        c24_proof: Mapping[str, Any] | None,
        issue: Mapping[str, str] | None = None,
    ) -> MacOSCleanHostReleaseEvidenceStageRecord:
        if self.journal.load_stage_record(stage) is not None:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence stage was already recorded: "
                + stage
            )
        evidence_document = {
            "schemaVersion": "v1",
            "evidenceKind": "macos-clean-host-release-stage",
            "runId": evidence_run.run_id,
            "releaseDeliveryPlanId": evidence_run.release_delivery_plan_id,
            "stage": stage,
            "status": status,
            "recordedAt": recorded_at,
            "releaseIdentity": release_identity_document(evidence_run),
            "details": dict(details),
        }
        if issue is not None:
            evidence_document["issue"] = dict(issue)
        evidence_path, evidence_sha256 = write_new_evidence_document(
            evidence_run.evidence_directory,
            stage,
            evidence_document,
        )
        if c24_proof is not None:
            mutable_proof = dict(c24_proof)
            mutable_proof["evidence"] = {
                "uri": evidence_path.as_uri(),
                "sha256": evidence_sha256,
            }
            c24_proof = mutable_proof
        stage_record = MacOSCleanHostReleaseEvidenceStageRecord(
            stage=stage,
            status=status,
            recorded_at=recorded_at,
            evidence_path=evidence_path,
            evidence_sha256=evidence_sha256,
            c24_proof=c24_proof,
        )
        self.journal.record_new_stage(stage_record, details)
        return stage_record


def create_macos_clean_host_release_evidence_run(
    journal_path: Path,
    evidence_directory: Path,
    installer_artifact_path: Path,
    release_delivery_plans_document: Path,
    release_delivery_plan_id: str,
    run_id: str,
    runner_id: str,
    command_contract: MacOSCleanHostReleaseEvidenceCommandContract,
) -> MacOSCleanHostReleaseEvidenceRun:
    """Bind one exact C23 macOS PKG byte stream to a new evidence journal."""

    validate_evidence_run_input_paths(
        journal_path,
        evidence_directory,
        installer_artifact_path,
        release_delivery_plans_document,
        command_contract,
    )
    if not run_id:
        raise MacOSCleanHostReleaseEvidenceRunError("macOS clean-Host evidence run ID is required")
    if not runner_id:
        raise MacOSCleanHostReleaseEvidenceRunError("macOS clean-Host runner ID is required")
    try:
        release_plan = load_selected_macos_host_package_release_plan(
            release_delivery_plans_document,
            release_delivery_plan_id,
        )
    except ProductDeliveryReleasePlanError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(str(error)) from error
    if installer_artifact_path.name != release_plan.expected_package_file_name:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host installer artifact file name must match C23 intended installer artifact"
        )
    evidence_run = evidence_run_from_release_plan(
        release_plan,
        installer_artifact_path,
        evidence_directory,
        run_id,
        runner_id,
        command_contract,
        utc_timestamp(),
    )
    MacOSCleanHostReleaseEvidenceJournal.create_new(journal_path, evidence_run)
    return evidence_run


def evidence_run_from_release_plan(
    release_plan: MacOSHostPackageReleasePlan,
    installer_artifact_path: Path,
    evidence_directory: Path,
    run_id: str,
    runner_id: str,
    command_contract: MacOSCleanHostReleaseEvidenceCommandContract,
    created_at: str,
) -> MacOSCleanHostReleaseEvidenceRun:
    return MacOSCleanHostReleaseEvidenceRun(
        run_id=run_id,
        runner_id=runner_id,
        release_delivery_plan_id=release_plan.release_delivery_plan_id,
        product_version=release_plan.product_version,
        intended_installer_file_name=release_plan.expected_package_file_name,
        macos_installer_package_identifier=(
            release_plan.macos_installer_package_identifier
        ),
        host_agent_launchd_service_label=(
            release_plan.host_agent_launchd_service_label
        ),
        host_edge_proxy_launchd_service_label=(
            release_plan.host_edge_proxy_launchd_service_label
        ),
        installer_artifact_path=installer_artifact_path,
        bound_installer_artifact_sha256=sha256_file(installer_artifact_path),
        evidence_directory=evidence_directory,
        command_contract=command_contract,
        created_at=created_at,
    )


def validate_evidence_run_input_paths(
    journal_path: Path,
    evidence_directory: Path,
    installer_artifact_path: Path,
    release_delivery_plans_document: Path,
    command_contract: MacOSCleanHostReleaseEvidenceCommandContract,
) -> None:
    if not journal_path.is_absolute() or journal_path.parent.is_dir() is False:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host evidence journal path must be absolute and have an existing parent directory"
        )
    if not evidence_directory.is_absolute() or not evidence_directory.is_dir():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host evidence directory must be an existing absolute directory"
        )
    if not installer_artifact_path.is_absolute() or not installer_artifact_path.is_file():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host installer artifact is missing or not an absolute file"
        )
    if (
        not release_delivery_plans_document.is_absolute()
        or not release_delivery_plans_document.is_file()
    ):
        raise MacOSCleanHostReleaseEvidenceRunError(
            "C23 release delivery plans document is missing or not an absolute file"
        )
    validate_command_contract(command_contract)


def validate_new_journal_path(journal_path: Path) -> None:
    if not journal_path.is_absolute() or not journal_path.parent.is_dir():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host release evidence journal path must be absolute and have an existing parent directory"
        )
    if journal_path.exists():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host release evidence journal already exists"
        )


def validate_command_contract(
    command_contract: MacOSCleanHostReleaseEvidenceCommandContract,
) -> None:
    for executable_name, executable_path in (
        ("pkgutil", command_contract.pkgutil_executable),
        ("installer", command_contract.installer_executable),
        ("launchctl", command_contract.launchctl_executable),
        ("sysctl", command_contract.sysctl_executable),
    ):
        if not executable_path.is_absolute() or not executable_path.is_file():
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host " + executable_name + " executable is missing or not an absolute file"
            )


def command_contract_document(
    command_contract: MacOSCleanHostReleaseEvidenceCommandContract,
) -> Mapping[str, str]:
    return {
        "pkgutilExecutable": str(command_contract.pkgutil_executable),
        "installerExecutable": str(command_contract.installer_executable),
        "launchctlExecutable": str(command_contract.launchctl_executable),
        "sysctlExecutable": str(command_contract.sysctl_executable),
    }


def command_contract_from_journal_document(
    document: Any,
) -> MacOSCleanHostReleaseEvidenceCommandContract:
    if not isinstance(document, dict):
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host release evidence command contract must be an object"
        )
    return MacOSCleanHostReleaseEvidenceCommandContract(
        pkgutil_executable=Path(
            required_non_empty_string(document.get("pkgutilExecutable"), "journal pkgutil executable")
        ),
        installer_executable=Path(
            required_non_empty_string(document.get("installerExecutable"), "journal installer executable")
        ),
        launchctl_executable=Path(
            required_non_empty_string(document.get("launchctlExecutable"), "journal launchctl executable")
        ),
        sysctl_executable=Path(
            required_non_empty_string(document.get("sysctlExecutable"), "journal sysctl executable")
        ),
    )


def assert_bound_installer_artifact_is_unchanged(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
) -> None:
    if (
        not evidence_run.installer_artifact_path.is_absolute()
        or not evidence_run.installer_artifact_path.is_file()
    ):
        raise MacOSCleanHostReleaseEvidenceRunError(
            "bound macOS clean-Host installer artifact is missing or not a file"
        )
    current_sha256 = sha256_file(evidence_run.installer_artifact_path)
    if current_sha256 != evidence_run.bound_installer_artifact_sha256:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "bound macOS clean-Host installer artifact SHA-256 changed after evidence run creation"
        )


def observed_installer_artifact(
    evidence_run: MacOSCleanHostReleaseEvidenceRun, observed_at: str
) -> Mapping[str, str]:
    assert_bound_installer_artifact_is_unchanged(evidence_run)
    return {
        "kind": "pkg",
        "fileName": evidence_run.intended_installer_file_name,
        "productVersion": evidence_run.product_version,
        "sha256": evidence_run.bound_installer_artifact_sha256,
        "observedAt": observed_at,
    }


def execute_macos_clean_host_command(
    executable: Path, arguments: Sequence[str]
) -> MacOSCleanHostReleaseEvidenceCommandObservation:
    """Execute a declared macOS command and retain its exact output as evidence."""

    try:
        completed = subprocess.run(
            [str(executable), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host command execution failed for "
            + str(executable)
            + ": "
            + str(error)
        ) from error
    return MacOSCleanHostReleaseEvidenceCommandObservation(
        executable=executable,
        arguments=tuple(arguments),
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def observe_macos_installer_artifact_release_identity(
    pkgutil_executable: Path,
    installer_artifact_path: Path,
) -> MacOSInstallerArtifactReleaseIdentityObservation:
    """Read flat-PKG PackageInfo through the portable macOS pkgutil command.

    macOS ``pkgutil`` exposes ``--pkg-info`` only for *installed* receipts;
    there is no ``--pkg-info-pkg`` command for an uninstalled flat PKG. The
    release runner therefore expands the bound artifact into its own temporary
    directory and reads PackageInfo. It never substitutes filename metadata.
    """

    with tempfile.TemporaryDirectory(
        prefix="vitalserver-macos-installer-artifact-metadata-"
    ) as temporary_directory:
        expanded_package_directory = Path(temporary_directory) / "expanded-package"
        package_expansion_command = execute_macos_clean_host_command(
            pkgutil_executable,
            ["--expand", str(installer_artifact_path), str(expanded_package_directory)],
        )
        if package_expansion_command.returncode != 0:
            return MacOSInstallerArtifactReleaseIdentityObservation(
                state="unavailable",
                package_identifier=None,
                product_version=None,
                package_expansion_command=package_expansion_command,
                reason="pkgutil package expansion returned a non-zero result",
            )
        package_info_path = expanded_package_directory / "PackageInfo"
        try:
            package_info = ElementTree.parse(package_info_path).getroot()
        except (OSError, ElementTree.ParseError) as error:
            return MacOSInstallerArtifactReleaseIdentityObservation(
                state="invalid",
                package_identifier=None,
                product_version=None,
                package_expansion_command=package_expansion_command,
                reason="expanded macOS PackageInfo cannot be decoded: " + str(error),
            )
        package_identifier = package_info.get("identifier")
        product_version = package_info.get("version")
        if not package_identifier or not product_version:
            return MacOSInstallerArtifactReleaseIdentityObservation(
                state="invalid",
                package_identifier=package_identifier,
                product_version=product_version,
                package_expansion_command=package_expansion_command,
                reason="expanded macOS PackageInfo requires identifier and version",
            )
        return MacOSInstallerArtifactReleaseIdentityObservation(
            state="available",
            package_identifier=package_identifier,
            product_version=product_version,
            package_expansion_command=package_expansion_command,
        )


def evaluate_macos_installer_artifact_integrity_issue(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    installer_artifact_release_identity: MacOSInstallerArtifactReleaseIdentityObservation,
    package_signature_command: MacOSCleanHostReleaseEvidenceCommandObservation,
) -> Mapping[str, str] | None:
    if installer_artifact_release_identity.state != "available":
        return {
            "code": "macos-package-metadata-unavailable",
            "message": "pkgutil could not provide readable metadata for the selected macOS installer artifact.",
        }
    if (
        installer_artifact_release_identity.package_identifier
        != evidence_run.macos_installer_package_identifier
    ):
        return {
            "code": "macos-package-identifier-mismatch",
            "message": "Selected macOS installer package metadata identifier does not match C23.",
        }
    if installer_artifact_release_identity.product_version != evidence_run.product_version:
        return {
            "code": "macos-package-version-mismatch",
            "message": "Selected macOS installer package metadata version does not match C23.",
        }
    if package_signature_command.returncode != 0:
        return {
            "code": "macos-package-signature-check-failed",
            "message": "pkgutil signature verification failed for the selected macOS installer artifact.",
        }
    signature_output = (
        package_signature_command.stdout + "\n" + package_signature_command.stderr
    ).lower()
    if "status: signed" not in signature_output or "no signature" in signature_output:
        return {
            "code": "macos-package-signature-not-accepted",
            "message": "The selected macOS installer artifact does not report an accepted package signature.",
        }
    return None


def observe_macos_package_receipt(
    pkgutil_executable: Path, package_identifier: str
) -> MacOSPackageReceiptObservation:
    command = execute_macos_clean_host_command(
        pkgutil_executable, ["--pkg-info", package_identifier]
    )
    if command.returncode == 0:
        try:
            metadata = parse_macos_installed_package_receipt_output(command.stdout)
        except MacOSCleanHostReleaseEvidenceRunError as error:
            return MacOSPackageReceiptObservation(
                state="invalid",
                package_identifier=None,
                product_version=None,
                command=command,
                reason=str(error),
            )
        return MacOSPackageReceiptObservation(
            state="installed",
            package_identifier=metadata.get("package-id"),
            product_version=metadata.get("version"),
            command=command,
        )
    output = (command.stdout + "\n" + command.stderr).lower()
    if any(marker in output for marker in EXPLICITLY_ABSENT_PACKAGE_RECEIPT_MARKERS):
        return MacOSPackageReceiptObservation(
            state="absent",
            package_identifier=None,
            product_version=None,
            command=command,
        )
    return MacOSPackageReceiptObservation(
        state="unavailable",
        package_identifier=None,
        product_version=None,
        command=command,
        reason="pkgutil did not explicitly report the C23 installer receipt as absent",
    )


def observe_required_launchd_service_registrations(
    launchctl_executable: Path,
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
) -> tuple[MacOSLaunchdServiceRegistrationObservation, ...]:
    return (
        observe_macos_launchd_service_registration(
            launchctl_executable,
            "host-agent",
            evidence_run.host_agent_launchd_service_label,
        ),
        observe_macos_launchd_service_registration(
            launchctl_executable,
            "host-edge-proxy",
            evidence_run.host_edge_proxy_launchd_service_label,
        ),
    )


def observe_macos_launchd_service_registration(
    launchctl_executable: Path, role: str, service_label: str
) -> MacOSLaunchdServiceRegistrationObservation:
    command = execute_macos_clean_host_command(
        launchctl_executable, ["print", "system/" + service_label]
    )
    if command.returncode == 0:
        state = "registered"
    else:
        output = (command.stdout + "\n" + command.stderr).lower()
        if any(
            marker in output
            for marker in EXPLICITLY_ABSENT_LAUNCHD_SERVICE_MARKERS
        ):
            state = "absent"
        else:
            state = "unavailable"
    return MacOSLaunchdServiceRegistrationObservation(
        role=role,
        service_label=service_label,
        state=state,
        command=command,
    )


def observe_macos_host_boot_session(
    sysctl_executable: Path,
) -> MacOSHostBootSessionObservation:
    command = execute_macos_clean_host_command(
        sysctl_executable, ["-n", "kern.bootsessionuuid"]
    )
    boot_session_identifier = command.stdout.strip()
    if command.returncode != 0 or not boot_session_identifier:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host boot session identifier is unavailable"
        )
    return MacOSHostBootSessionObservation(
        boot_session_identifier=boot_session_identifier,
        command=command,
    )


def clean_host_preflight_issue(
    package_receipt: MacOSPackageReceiptObservation,
    service_observations: Sequence[MacOSLaunchdServiceRegistrationObservation],
) -> Mapping[str, str] | None:
    if package_receipt.state == "installed":
        return {
            "code": "macos-clean-host-package-receipt-already-installed",
            "message": "The C23 macOS installer receipt is already installed, so this Host is not clean.",
        }
    if package_receipt.state != "absent":
        return {
            "code": "macos-clean-host-package-receipt-observation-unavailable",
            "message": "The C23 macOS installer receipt absence could not be observed explicitly.",
        }
    for observation in service_observations:
        if observation.state == "registered":
            return {
                "code": "macos-clean-host-service-already-registered",
                "message": "A C23-required launchd service is already registered, so this Host is not clean.",
            }
        if observation.state != "absent":
            return {
                "code": "macos-clean-host-service-observation-unavailable",
                "message": "A C23-required launchd service absence could not be observed explicitly.",
            }
    return None


def clean_install_issue(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    installer_command: MacOSCleanHostReleaseEvidenceCommandObservation,
    package_receipt: MacOSPackageReceiptObservation,
) -> Mapping[str, str] | None:
    if installer_command.returncode != 0:
        return {
            "code": "macos-clean-install-command-failed",
            "message": "macOS installer returned a non-zero result for the selected C23 package.",
        }
    return installed_package_receipt_issue(evidence_run, package_receipt)


def installed_receipt_or_service_registration_issue(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    package_receipt: MacOSPackageReceiptObservation,
    service_observations: Sequence[MacOSLaunchdServiceRegistrationObservation],
) -> Mapping[str, str] | None:
    receipt_issue = installed_package_receipt_issue(evidence_run, package_receipt)
    if receipt_issue is not None:
        return receipt_issue
    for observation in service_observations:
        if observation.state != "registered":
            return {
                "code": "macos-launchd-service-registration-not-observed",
                "message": "A C23-required launchd service was not observed as registered.",
            }
    return None


def installed_package_receipt_issue(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    package_receipt: MacOSPackageReceiptObservation,
) -> Mapping[str, str] | None:
    if package_receipt.state != "installed":
        return {
            "code": "macos-installed-package-receipt-not-observed",
            "message": "The C23 macOS installer receipt was not observed as installed after the installer effect.",
        }
    if package_receipt.package_identifier != evidence_run.macos_installer_package_identifier:
        return {
            "code": "macos-installed-package-receipt-identifier-mismatch",
            "message": "The observed macOS installer receipt identifier does not match C23.",
        }
    if package_receipt.product_version != evidence_run.product_version:
        return {
            "code": "macos-installed-package-receipt-version-mismatch",
            "message": "The observed macOS installer receipt version does not match C23.",
        }
    return None


def reboot_persistence_issue(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    checkpoint_session_identifier: str,
    current_boot_session: MacOSHostBootSessionObservation,
    package_receipt: MacOSPackageReceiptObservation,
    service_observations: Sequence[MacOSLaunchdServiceRegistrationObservation],
) -> Mapping[str, str] | None:
    if current_boot_session.boot_session_identifier == checkpoint_session_identifier:
        return {
            "code": "macos-reboot-not-observed",
            "message": "The macOS boot-session identifier did not change after the reboot checkpoint.",
        }
    return installed_receipt_or_service_registration_issue(
        evidence_run, package_receipt, service_observations
    )


def compose_verified_c24_proof(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    stage: str,
    recorded_at: str,
    observed_artifact: Mapping[str, str],
    optional_stage_observation: Any | None = None,
) -> Mapping[str, Any]:
    proof: dict[str, Any] = {
        "planId": evidence_run.release_delivery_plan_id,
        "platform": "macos",
        "providerKind": "macos-virtualization",
        "stage": stage,
        "status": "verified",
        "recordedAt": recorded_at,
        "runner": {"kind": "macos-clean-host", "id": evidence_run.runner_id},
        "observedInstallerArtifact": dict(observed_artifact),
    }
    if stage == CLEAN_INSTALL_STAGE:
        proof["observedMacOSInstallerReceipt"] = optional_stage_observation
    if stage == SERVICE_REGISTRATION_STAGE:
        proof["observedHostServiceRegistrations"] = optional_stage_observation
    return proof


def compose_failed_c24_proof(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    stage: str,
    recorded_at: str,
    issue: Mapping[str, str],
) -> Mapping[str, Any]:
    return {
        "planId": evidence_run.release_delivery_plan_id,
        "platform": "macos",
        "providerKind": "macos-virtualization",
        "stage": stage,
        "status": "failed",
        "recordedAt": recorded_at,
        "runner": {"kind": "macos-clean-host", "id": evidence_run.runner_id},
        "issue": dict(issue),
    }


def observed_macos_installer_receipt(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    package_receipt: MacOSPackageReceiptObservation,
    observed_at: str,
) -> Mapping[str, str]:
    receipt_issue = installed_package_receipt_issue(evidence_run, package_receipt)
    if receipt_issue is not None:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "cannot compose an observed macOS installer receipt: "
            + receipt_issue["code"]
        )
    return {
        "packageIdentifier": evidence_run.macos_installer_package_identifier,
        "productVersion": evidence_run.product_version,
        "receiptState": "installed",
        "observedAt": observed_at,
    }


def observed_host_service_registrations(
    service_observations: Sequence[MacOSLaunchdServiceRegistrationObservation],
    observed_at: str,
) -> list[Mapping[str, str]]:
    registrations: list[Mapping[str, str]] = []
    for observation in service_observations:
        if observation.state != "registered":
            raise MacOSCleanHostReleaseEvidenceRunError(
                "cannot compose an observed launchd service registration from "
                + observation.state
            )
        registrations.append(
            {
                "role": observation.role,
                "manager": "launchd",
                "name": observation.service_label,
                "registrationState": "registered",
                "observedAt": observed_at,
            }
        )
    return registrations


def release_identity_document(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
) -> Mapping[str, str]:
    return {
        "productVersion": evidence_run.product_version,
        "intendedInstallerFileName": evidence_run.intended_installer_file_name,
        "macOSInstallerPackageIdentifier": (
            evidence_run.macos_installer_package_identifier
        ),
        "hostAgentLaunchdServiceLabel": (
            evidence_run.host_agent_launchd_service_label
        ),
        "hostEdgeProxyLaunchdServiceLabel": (
            evidence_run.host_edge_proxy_launchd_service_label
        ),
        "boundInstallerArtifactSHA256": evidence_run.bound_installer_artifact_sha256,
    }


def command_document(
    command: MacOSCleanHostReleaseEvidenceCommandObservation,
) -> Mapping[str, Any]:
    return {
        "executable": str(command.executable),
        "arguments": list(command.arguments),
        "returnCode": command.returncode,
        "stdout": command.stdout,
        "stderr": command.stderr,
    }


def installer_artifact_release_identity_document(
    installer_artifact_release_identity: MacOSInstallerArtifactReleaseIdentityObservation,
) -> Mapping[str, Any]:
    return {
        "state": installer_artifact_release_identity.state,
        "packageIdentifier": installer_artifact_release_identity.package_identifier,
        "productVersion": installer_artifact_release_identity.product_version,
        "reason": installer_artifact_release_identity.reason,
        "packageExpansionCommand": command_document(
            installer_artifact_release_identity.package_expansion_command
        ),
    }


def package_receipt_document(
    package_receipt: MacOSPackageReceiptObservation,
) -> Mapping[str, Any]:
    return {
        "state": package_receipt.state,
        "packageIdentifier": package_receipt.package_identifier,
        "productVersion": package_receipt.product_version,
        "reason": package_receipt.reason,
        "command": command_document(package_receipt.command),
    }


def launchd_service_registration_document(
    service_observation: MacOSLaunchdServiceRegistrationObservation,
) -> Mapping[str, Any]:
    return {
        "role": service_observation.role,
        "serviceLabel": service_observation.service_label,
        "state": service_observation.state,
        "command": command_document(service_observation.command),
    }


def boot_session_document(
    boot_session: MacOSHostBootSessionObservation,
) -> Mapping[str, Any]:
    return {
        "bootSessionIdentifier": boot_session.boot_session_identifier,
        "command": command_document(boot_session.command),
    }


def boot_session_identifier_from_checkpoint(
    checkpoint_details: Mapping[str, Any],
) -> str:
    boot_session = checkpoint_details.get("bootSessionObservation")
    if not isinstance(boot_session, dict):
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host reboot checkpoint has no boot-session observation"
        )
    return required_non_empty_string(
        boot_session.get("bootSessionIdentifier"),
        "macOS clean-Host reboot checkpoint boot-session identifier",
    )


def parse_macos_installed_package_receipt_output(output: str) -> Mapping[str, str]:
    metadata: dict[str, str] = {}
    for line in output.splitlines():
        key, separator, value = line.partition(":")
        if separator and key and value.strip():
            metadata[key.strip()] = value.strip()
    if not metadata.get("package-id") or not metadata.get("version"):
        raise MacOSCleanHostReleaseEvidenceRunError(
            "pkgutil output does not contain package-id and version"
        )
    return metadata


def write_new_evidence_document(
    evidence_directory: Path,
    stage: str,
    evidence_document: Mapping[str, Any],
) -> tuple[Path, str]:
    validate_release_evidence_stage(stage)
    if not evidence_directory.is_absolute() or not evidence_directory.is_dir():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host evidence directory is missing or not an absolute directory"
        )
    evidence_path = evidence_directory / (stage + ".json")
    if evidence_path.exists():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host evidence document already exists for stage: " + stage
        )
    document_bytes = (canonical_json(evidence_document) + "\n").encode("utf-8")
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=evidence_directory, prefix="." + stage + ".", delete=False
        ) as temporary_file:
            temporary_file.write(document_bytes)
            temporary_path = Path(temporary_file.name)
        os.replace(temporary_path, evidence_path)
    except OSError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host evidence document write failed: " + str(error)
        ) from error
    return evidence_path, sha256_file(evidence_path)


def stage_record_document(
    stage_record: MacOSCleanHostReleaseEvidenceStageRecord,
) -> Mapping[str, Any]:
    return {
        "stage": stage_record.stage,
        "status": stage_record.status,
        "recordedAt": stage_record.recorded_at,
        "evidencePath": str(stage_record.evidence_path),
        "evidenceSHA256": stage_record.evidence_sha256,
        "c24Proof": stage_record.c24_proof,
    }


def validate_release_evidence_stage(stage: str) -> None:
    if stage not in RELEASE_EVIDENCE_STAGES:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "unknown macOS clean-Host release evidence stage: " + stage
        )


def required_non_empty_string(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise MacOSCleanHostReleaseEvidenceRunError(name + " must be a non-empty string")
    return value


def required_sha256(value: Any, name: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise MacOSCleanHostReleaseEvidenceRunError(name + " must be a lowercase SHA-256")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host file digest read failed: " + str(error)
        ) from error
    return digest.hexdigest()


def canonical_json(document: Any) -> str:
    return json.dumps(document, sort_keys=True, separators=(",", ":"))


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def require_macos_host_platform() -> None:
    if platform.system() != "Darwin":
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host release evidence runner requires a Darwin Host"
        )


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)

    create_run = subcommands.add_parser(
        "create-run", help="create a new explicit release evidence journal"
    )
    create_run.add_argument("--journal-path", required=True)
    create_run.add_argument("--evidence-directory", required=True)
    create_run.add_argument("--installer-artifact", required=True)
    create_run.add_argument("--release-delivery-plans-document", required=True)
    create_run.add_argument("--release-delivery-plan-id", required=True)
    create_run.add_argument("--run-id", required=True)
    create_run.add_argument("--runner-id", required=True)
    create_run.add_argument("--pkgutil-executable", required=True)
    create_run.add_argument("--installer-executable", required=True)
    create_run.add_argument("--launchctl-executable", required=True)
    create_run.add_argument("--sysctl-executable", required=True)

    for command_name in (
        "record-artifact-integrity",
        "record-clean-host-preflight",
        "record-service-registration",
        "record-reboot-checkpoint",
        "record-reboot",
        "print-stage-proof",
    ):
        command = subcommands.add_parser(command_name)
        command.add_argument("--journal-path", required=True)
        if command_name == "print-stage-proof":
            command.add_argument(
                "--stage",
                required=True,
                choices=(
                    ARTIFACT_INTEGRITY_STAGE,
                    CLEAN_INSTALL_STAGE,
                    SERVICE_REGISTRATION_STAGE,
                    REBOOT_STAGE,
                ),
            )

    clean_install = subcommands.add_parser("execute-clean-install")
    clean_install.add_argument("--journal-path", required=True)
    clean_install.add_argument(
        "--authorize-clean-install",
        action="store_true",
        help="explicitly authorize the irreversible macOS installer effect",
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        if parsed.command == "create-run":
            evidence_run = create_macos_clean_host_release_evidence_run(
                journal_path=Path(parsed.journal_path),
                evidence_directory=Path(parsed.evidence_directory),
                installer_artifact_path=Path(parsed.installer_artifact),
                release_delivery_plans_document=Path(
                    parsed.release_delivery_plans_document
                ),
                release_delivery_plan_id=parsed.release_delivery_plan_id,
                run_id=parsed.run_id,
                runner_id=parsed.runner_id,
                command_contract=MacOSCleanHostReleaseEvidenceCommandContract(
                    pkgutil_executable=Path(parsed.pkgutil_executable),
                    installer_executable=Path(parsed.installer_executable),
                    launchctl_executable=Path(parsed.launchctl_executable),
                    sysctl_executable=Path(parsed.sysctl_executable),
                ),
            )
            print(canonical_json({"evidenceRun": evidence_run_document(evidence_run)}))
            return 0

        require_macos_host_platform()
        journal = MacOSCleanHostReleaseEvidenceJournal(Path(parsed.journal_path))
        evidence_runner = MacOSCleanHostReleaseEvidenceRunner(journal)
        if parsed.command == "record-artifact-integrity":
            stage_record = evidence_runner.record_artifact_integrity()
        elif parsed.command == "record-clean-host-preflight":
            stage_record = evidence_runner.record_clean_host_preflight()
        elif parsed.command == "execute-clean-install":
            if not parsed.authorize_clean_install:
                raise MacOSCleanHostReleaseEvidenceRunError(
                    "execute-clean-install requires --authorize-clean-install"
                )
            stage_record = evidence_runner.execute_clean_install()
        elif parsed.command == "record-service-registration":
            stage_record = evidence_runner.record_service_registration()
        elif parsed.command == "record-reboot-checkpoint":
            stage_record = evidence_runner.record_reboot_checkpoint()
        elif parsed.command == "record-reboot":
            stage_record = evidence_runner.record_reboot()
        elif parsed.command == "print-stage-proof":
            stage_record = journal.load_stage_record(parsed.stage)
            if stage_record is None or stage_record.c24_proof is None:
                raise MacOSCleanHostReleaseEvidenceRunError(
                    "macOS clean-Host release evidence stage has no C24 proof: "
                    + parsed.stage
                )
            print(canonical_json(stage_record.c24_proof))
            return 0
        else:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "unknown macOS clean-Host release evidence command"
            )
        print(canonical_json(stage_record_document(stage_record)))
        return 0
    except MacOSCleanHostReleaseEvidenceRunError as error:
        print("macOS clean-Host release evidence failed: " + str(error), file=sys.stderr)
        return 1


def evidence_run_document(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
) -> Mapping[str, Any]:
    document = asdict(evidence_run)
    document["installer_artifact_path"] = str(evidence_run.installer_artifact_path)
    document["evidence_directory"] = str(evidence_run.evidence_directory)
    document["command_contract"] = command_contract_document(
        evidence_run.command_contract
    )
    return document


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
