#!/usr/bin/env python3
"""Collect explicit Linux clean-Host C24 release-delivery evidence.

This release-process workflow owns a ``LinuxCleanHostReleaseEvidenceRun`` and
its SQLite journal. dpkg, systemd, Linux filesystem, and kernel boot ID remain
external facts observed through the explicit command contract. The runner does
not use package file names, a successful `dpkg --install` exit code, or an old
journal row as a substitute for package receipt, service registration, or
reboot evidence.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import sqlite3
import sys
import tempfile
from typing import Any, Mapping, Sequence

from tooling import host_platform_release_transition_evidence
from tooling import linux_host_installation_observation
from tooling.product_delivery_release_plan import (
    LinuxHostDEBReleasePlan,
    ProductDeliveryReleasePlanError,
    load_selected_linux_host_deb_release_plan,
)


class LinuxCleanHostReleaseEvidenceRunError(RuntimeError):
    """A Linux clean-Host C24 evidence state is unavailable or invalid."""


ARTIFACT_INTEGRITY_STAGE = "artifact-integrity"
CLEAN_HOST_PREFLIGHT_STAGE = "clean-host-preflight"
CLEAN_INSTALL_STAGE = "clean-install"
SERVICE_REGISTRATION_STAGE = "service-registration"
REBOOT_CHECKPOINT_STAGE = "reboot-checkpoint"
REBOOT_STAGE = "reboot"
UPDATE_STAGE = "update"
ROLLBACK_STAGE = "rollback"
UNINSTALL_REINSTALL_STAGE = "uninstall-reinstall"

C24_PROOF_STAGES = (
    ARTIFACT_INTEGRITY_STAGE,
    CLEAN_INSTALL_STAGE,
    SERVICE_REGISTRATION_STAGE,
    REBOOT_STAGE,
    UNINSTALL_REINSTALL_STAGE,
    UPDATE_STAGE,
    ROLLBACK_STAGE,
)
RELEASE_EVIDENCE_STAGES = {
    ARTIFACT_INTEGRITY_STAGE,
    CLEAN_HOST_PREFLIGHT_STAGE,
    CLEAN_INSTALL_STAGE,
    SERVICE_REGISTRATION_STAGE,
    REBOOT_CHECKPOINT_STAGE,
    REBOOT_STAGE,
    UPDATE_STAGE,
    ROLLBACK_STAGE,
    UNINSTALL_REINSTALL_STAGE,
}


@dataclass(frozen=True)
class LinuxCleanHostReleaseEvidenceCommandContract:
    dpkg_deb_executable: Path
    dpkg_executable: Path
    dpkg_query_executable: Path
    systemctl_executable: Path
    test_executable: Path
    cat_executable: Path
    boot_id_path: Path


@dataclass(frozen=True)
class LinuxCleanHostReleaseEvidenceRun:
    run_id: str
    runner_id: str
    release_delivery_plan_id: str
    product_version: str
    intended_installer_file_name: str
    debian_package_identifier: str
    host_agent_systemd_service_name: str
    host_edge_proxy_systemd_service_name: str
    host_update_handoff_supervisor_systemd_service_name: str
    product_installation_root: Path
    product_data_root: Path
    installer_artifact_path: Path
    bound_installer_artifact_sha256: str
    evidence_directory: Path
    command_contract: LinuxCleanHostReleaseEvidenceCommandContract
    created_at: str


@dataclass(frozen=True)
class LinuxCleanHostReleaseEvidenceStageRecord:
    stage: str
    status: str
    recorded_at: str
    evidence_path: Path
    evidence_sha256: str
    c24_proof: Mapping[str, Any] | None


class LinuxCleanHostReleaseEvidenceJournal:
    """SQLite owner for Linux C24 collection, independent from Host state."""

    def __init__(self, journal_path: Path):
        self.journal_path = journal_path

    @classmethod
    def create_new(
        cls, journal_path: Path, evidence_run: LinuxCleanHostReleaseEvidenceRun
    ) -> "LinuxCleanHostReleaseEvidenceJournal":
        if not journal_path.is_absolute() or not journal_path.parent.is_dir():
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host evidence journal path must be absolute and have an existing parent directory"
            )
        if journal_path.exists():
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence journal already exists"
            )
        try:
            with sqlite3.connect(journal_path) as connection:
                connection.executescript(
                    """
                    CREATE TABLE evidence_run (
                        run_id TEXT PRIMARY KEY,
                        payload_json TEXT NOT NULL
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
                    "INSERT INTO evidence_run (run_id, payload_json) VALUES (?, ?)",
                    (evidence_run.run_id, canonical_json(evidence_run_document(evidence_run))),
                )
        except sqlite3.Error as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence journal create failed: " + str(error)
            ) from error
        return cls(journal_path)

    def load_evidence_run(self) -> LinuxCleanHostReleaseEvidenceRun:
        connection = self.open_existing_connection()
        try:
            row = connection.execute("SELECT payload_json FROM evidence_run").fetchone()
        except sqlite3.Error as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence journal read failed: " + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence journal has no evidence run"
            )
        try:
            document = json.loads(row["payload_json"])
        except (TypeError, json.JSONDecodeError) as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence run is unreadable"
            ) from error
        return evidence_run_from_document(document)

    def load_stage_record(
        self, stage: str
    ) -> LinuxCleanHostReleaseEvidenceStageRecord | None:
        validate_release_evidence_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT * FROM evidence_stage WHERE stage = ?", (stage,)
            ).fetchone()
        except sqlite3.Error as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage read failed: " + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            return None
        try:
            proof = json.loads(row["c24_proof_json"]) if row["c24_proof_json"] else None
        except (TypeError, json.JSONDecodeError) as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence C24 proof is unreadable"
            ) from error
        if proof is not None and not isinstance(proof, dict):
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence C24 proof must be an object"
            )
        return LinuxCleanHostReleaseEvidenceStageRecord(
            stage=stage,
            status=required_string(row["status"], "journal stage status"),
            recorded_at=required_string(row["recorded_at"], "journal stage time"),
            evidence_path=Path(required_string(row["evidence_path"], "journal evidence path")),
            evidence_sha256=required_sha256(row["evidence_sha256"], "journal evidence SHA-256"),
            c24_proof=proof,
        )

    def load_stage_details(self, stage: str) -> Mapping[str, Any]:
        validate_release_evidence_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT details_json FROM evidence_stage WHERE stage = ?", (stage,)
            ).fetchone()
        except sqlite3.Error as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage details read failed: " + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage is not recorded: " + stage
            )
        try:
            details = json.loads(row["details_json"])
        except (TypeError, json.JSONDecodeError) as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage details are unreadable"
            ) from error
        if not isinstance(details, dict):
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage details must be an object"
            )
        return details

    def record_new_stage(
        self,
        stage_record: LinuxCleanHostReleaseEvidenceStageRecord,
        details: Mapping[str, Any],
    ) -> None:
        validate_release_evidence_stage(stage_record.stage)
        if stage_record.status not in {"verified", "failed"}:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage status must be verified or failed"
            )
        connection = self.open_existing_connection()
        try:
            if connection.execute(
                "SELECT 1 FROM evidence_stage WHERE stage = ?", (stage_record.stage,)
            ).fetchone() is not None:
                raise LinuxCleanHostReleaseEvidenceRunError(
                    "Linux clean-Host release evidence stage was already recorded: "
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
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage write failed: " + str(error)
            ) from error
        finally:
            connection.close()

    def open_existing_connection(self) -> sqlite3.Connection:
        if not self.journal_path.is_absolute() or not self.journal_path.is_file():
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence journal is missing or not a file"
            )
        try:
            connection = sqlite3.connect(self.journal_path)
            connection.row_factory = sqlite3.Row
            columns = {
                row["name"] for row in connection.execute("PRAGMA table_info(evidence_run)")
            }
        except sqlite3.Error as error:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence journal open failed: " + str(error)
            ) from error
        if columns != {"run_id", "payload_json"}:
            connection.close()
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence journal has an unsupported schema"
            )
        return connection


class LinuxCleanHostReleaseEvidenceRunner:
    """Application workflow for explicit Linux C24 evidence transitions."""

    def __init__(self, journal: LinuxCleanHostReleaseEvidenceJournal):
        self.journal = journal

    def record_artifact_integrity(self) -> LinuxCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.journal.load_evidence_run()
        observed_at = utc_timestamp()
        artifact = observed_installer_artifact(evidence_run, observed_at)
        identity = observe_linux_deb_artifact_release_identity(evidence_run)
        issue = deb_artifact_integrity_issue(evidence_run, identity)
        return self.record_stage(
            evidence_run,
            ARTIFACT_INTEGRITY_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                "observedInstallerArtifact": artifact,
                "debArtifactIdentityObservation": linux_host_installation_observation.deb_artifact_identity_document(identity),
            },
            compose_verified_c24_proof(
                evidence_run, ARTIFACT_INTEGRITY_STAGE, observed_at, artifact
            )
            if issue is None
            else compose_failed_c24_proof(
                evidence_run, ARTIFACT_INTEGRITY_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_clean_host_preflight(self) -> LinuxCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_predecessor(ARTIFACT_INTEGRITY_STAGE)
        observed_at = utc_timestamp()
        registration = observe_linux_deb_package_registration(evidence_run)
        services = observe_required_systemd_services(evidence_run)
        roots = observe_required_roots(evidence_run)
        issue = clean_host_preflight_issue(registration, services, roots)
        return self.record_stage(
            evidence_run,
            CLEAN_HOST_PREFLIGHT_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            observation_details(registration, services, roots),
            None,
            issue,
        )

    def execute_clean_install(self) -> LinuxCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_predecessor(CLEAN_HOST_PREFLIGHT_STAGE)
        observed_at = utc_timestamp()
        installer_command = execute_linux_clean_host_command(
            evidence_run.command_contract.dpkg_executable,
            ["--install", str(evidence_run.installer_artifact_path)],
        )
        registration = observe_linux_deb_package_registration(evidence_run)
        issue = clean_install_issue(evidence_run, installer_command, registration)
        artifact = observed_installer_artifact(evidence_run, observed_at)
        return self.record_stage(
            evidence_run,
            CLEAN_INSTALL_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                "installerCommand": linux_host_installation_observation.command_document(installer_command),
                "debPackageRegistrationObservation": linux_host_installation_observation.deb_package_registration_document(registration),
                "observedInstallerArtifact": artifact,
            },
            compose_verified_c24_proof(evidence_run, CLEAN_INSTALL_STAGE, observed_at, artifact)
            if issue is None
            else compose_failed_c24_proof(evidence_run, CLEAN_INSTALL_STAGE, observed_at, issue),
            issue,
        )

    def record_service_registration(self) -> LinuxCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_predecessor(CLEAN_INSTALL_STAGE)
        observed_at = utc_timestamp()
        registration = observe_linux_deb_package_registration(evidence_run)
        services = observe_required_systemd_services(evidence_run)
        roots = observe_required_roots(evidence_run)
        issue = installed_receipt_or_service_registration_issue(
            evidence_run, registration, services, roots
        )
        artifact = observed_installer_artifact(evidence_run, observed_at)
        return self.record_stage(
            evidence_run,
            SERVICE_REGISTRATION_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                **observation_details(registration, services, roots),
                "observedInstallerArtifact": artifact,
            },
            compose_verified_c24_proof(
                evidence_run,
                SERVICE_REGISTRATION_STAGE,
                observed_at,
                artifact,
                observed_host_service_registrations(services, observed_at),
            )
            if issue is None
            else compose_failed_c24_proof(
                evidence_run, SERVICE_REGISTRATION_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_reboot_checkpoint(self) -> LinuxCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_predecessor(SERVICE_REGISTRATION_STAGE)
        observed_at = utc_timestamp()
        boot_session = observe_linux_host_boot_session(evidence_run)
        return self.record_stage(
            evidence_run,
            REBOOT_CHECKPOINT_STAGE,
            "verified",
            observed_at,
            {"bootSessionObservation": linux_host_installation_observation.boot_session_document(boot_session)},
            None,
        )

    def record_reboot(self) -> LinuxCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_predecessor(REBOOT_CHECKPOINT_STAGE)
        checkpoint = boot_session_identifier_from_checkpoint(
            self.journal.load_stage_details(REBOOT_CHECKPOINT_STAGE)
        )
        observed_at = utc_timestamp()
        current_boot_session = observe_linux_host_boot_session(evidence_run)
        registration = observe_linux_deb_package_registration(evidence_run)
        services = observe_required_systemd_services(evidence_run)
        roots = observe_required_roots(evidence_run)
        issue = reboot_persistence_issue(
            evidence_run, checkpoint, current_boot_session, registration, services, roots
        )
        artifact = observed_installer_artifact(evidence_run, observed_at)
        return self.record_stage(
            evidence_run,
            REBOOT_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                "preRebootBootSessionIdentifier": checkpoint,
                "postRebootBootSessionObservation": linux_host_installation_observation.boot_session_document(current_boot_session),
                **observation_details(registration, services, roots),
                "observedInstallerArtifact": artifact,
            },
            compose_verified_c24_proof(evidence_run, REBOOT_STAGE, observed_at, artifact)
            if issue is None
            else compose_failed_c24_proof(evidence_run, REBOOT_STAGE, observed_at, issue),
            issue,
        )

    def record_host_platform_update(
        self,
        release_delivery_plans_document: Path,
        host_update_journal_path: Path,
        host_platform_effect_receipt_path: Path,
        host_installation_manifest_path: Path,
        host_installation_footprint_path: Path,
    ) -> LinuxCleanHostReleaseEvidenceStageRecord:
        """Bind a successful C29/C28/C55 update to fresh Linux observations.

        The transition reader proves contract correlation and C48/C49 facts.
        This C24 owner separately observes dpkg, systemd, and product roots at
        collection time.  Neither set of facts substitutes for the other.
        """

        return self.record_host_platform_transition(
            UPDATE_STAGE,
            REBOOT_STAGE,
            release_delivery_plans_document,
            host_update_journal_path,
            host_platform_effect_receipt_path,
            host_installation_manifest_path,
            host_installation_footprint_path,
        )

    def record_host_platform_rollback(
        self,
        release_delivery_plans_document: Path,
        host_update_journal_path: Path,
        host_platform_effect_receipt_path: Path,
        host_installation_manifest_path: Path,
        host_installation_footprint_path: Path,
    ) -> LinuxCleanHostReleaseEvidenceStageRecord:
        """Bind a failed update's explicit rollback to fresh Linux facts."""

        return self.record_host_platform_transition(
            ROLLBACK_STAGE,
            REBOOT_STAGE,
            release_delivery_plans_document,
            host_update_journal_path,
            host_platform_effect_receipt_path,
            host_installation_manifest_path,
            host_installation_footprint_path,
        )

    def record_host_platform_transition(
        self,
        stage: str,
        predecessor_stage: str,
        release_delivery_plans_document: Path,
        host_update_journal_path: Path,
        host_platform_effect_receipt_path: Path,
        host_installation_manifest_path: Path,
        host_installation_footprint_path: Path,
    ) -> LinuxCleanHostReleaseEvidenceStageRecord:
        other_transition_stage = (
            ROLLBACK_STAGE if stage == UPDATE_STAGE else UPDATE_STAGE
        )
        if self.journal.load_stage_record(other_transition_stage) is not None:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence run cannot mix update and rollback "
                "transition scenarios"
            )
        evidence_run = self.require_predecessor(predecessor_stage)
        observed_at = utc_timestamp()
        transition, issue = observe_host_platform_transition(
            stage,
            evidence_run,
            release_delivery_plans_document,
            host_update_journal_path,
            host_platform_effect_receipt_path,
            host_installation_manifest_path,
            host_installation_footprint_path,
        )
        registration = observe_linux_deb_package_registration(evidence_run)
        services = observe_required_systemd_services(evidence_run)
        roots = observe_required_roots(evidence_run)
        if issue is None and transition is not None:
            issue = host_platform_transition_os_issue(
                stage, evidence_run, transition, registration, services, roots
            )
        artifact = observed_installer_artifact(evidence_run, observed_at)
        details: dict[str, Any] = {
            **observation_details(registration, services, roots),
            "observedInstallerArtifact": artifact,
        }
        if transition is not None:
            details["hostPlatformReleaseTransition"] = (
                host_platform_release_transition_evidence.release_transition_evidence_document(
                    transition
                )
            )
        else:
            details["hostPlatformReleaseTransitionInput"] = {
                "releaseDeliveryPlansDocument": str(release_delivery_plans_document),
                "hostUpdateJournalPath": str(host_update_journal_path),
                "hostPlatformEffectReceiptPath": str(host_platform_effect_receipt_path),
                "hostInstallationManifestPath": str(host_installation_manifest_path),
                "hostInstallationFootprintPath": str(host_installation_footprint_path),
            }
        return self.record_stage(
            evidence_run,
            stage,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            compose_verified_c24_proof(evidence_run, stage, observed_at, artifact)
            if issue is None
            else compose_failed_c24_proof(evidence_run, stage, observed_at, issue),
            issue,
        )

    def execute_uninstall_reinstall_preserving_data(
        self,
        removal_receipt_path: Path,
        expected_removal_installation_id: str,
        expected_removal_release_id: str,
    ) -> LinuxCleanHostReleaseEvidenceStageRecord:
        """Prove explicit C54 preserve removal before one explicit reinstall.

        Linux normal removal leaves the dpkg configuration receipt while the
        C48-owned mutable store remains by the operator's explicit C54 choice.
        A package-manager exit code, missing service, or a receipt from another
        product is not enough to advance to reinstallation.
        """

        evidence_run = self.require_predecessor(REBOOT_STAGE)
        observed_at = utc_timestamp()
        removal_command = execute_linux_clean_host_command(
            evidence_run.command_contract.dpkg_executable,
            ["--remove", evidence_run.debian_package_identifier],
        )
        removal_registration = observe_linux_deb_package_registration(evidence_run)
        removal_services = observe_required_systemd_services(evidence_run)
        removal_roots = observe_required_roots(evidence_run)
        removal_receipt, removal_receipt_sha256, removal_receipt_issue = (
            observe_completed_linux_preservation_removal_receipt(
                removal_receipt_path,
                expected_removal_installation_id,
                expected_removal_release_id,
            )
        )
        removal_issue = uninstall_preserving_data_issue(
            removal_command,
            removal_registration,
            removal_services,
            removal_roots,
            removal_receipt_issue,
        )
        artifact = observed_installer_artifact(evidence_run, observed_at)
        removal_details: dict[str, Any] = {
            "dataDisposition": "preserve-mutable-data",
            "uninstallCommand": linux_host_installation_observation.command_document(removal_command),
            **observation_details(removal_registration, removal_services, removal_roots),
        }
        if removal_receipt is not None and removal_receipt_sha256 is not None:
            removal_details["hostProductRemovalReceipt"] = {
                "uri": removal_receipt_path.as_uri(),
                "sha256": removal_receipt_sha256,
                "receipt": removal_receipt,
            }
        if removal_issue is not None:
            return self.record_stage(
                evidence_run,
                UNINSTALL_REINSTALL_STAGE,
                "failed",
                observed_at,
                removal_details,
                compose_failed_c24_proof(
                    evidence_run, UNINSTALL_REINSTALL_STAGE, observed_at, removal_issue
                ),
                removal_issue,
            )

        reinstall_command = execute_linux_clean_host_command(
            evidence_run.command_contract.dpkg_executable,
            ["--install", str(evidence_run.installer_artifact_path)],
        )
        reinstall_registration = observe_linux_deb_package_registration(evidence_run)
        reinstall_services = observe_required_systemd_services(evidence_run)
        reinstall_roots = observe_required_roots(evidence_run)
        reinstall_issue = reinstall_after_preserving_removal_issue(
            evidence_run,
            reinstall_command,
            reinstall_registration,
            reinstall_services,
            reinstall_roots,
        )
        details = {
            **removal_details,
            "reinstallCommand": linux_host_installation_observation.command_document(reinstall_command),
            "postReinstall": observation_details(
                reinstall_registration, reinstall_services, reinstall_roots
            ),
            "observedInstallerArtifact": artifact,
        }
        return self.record_stage(
            evidence_run,
            UNINSTALL_REINSTALL_STAGE,
            "verified" if reinstall_issue is None else "failed",
            observed_at,
            details,
            compose_verified_c24_proof(
                evidence_run, UNINSTALL_REINSTALL_STAGE, observed_at, artifact
            )
            if reinstall_issue is None
            else compose_failed_c24_proof(
                evidence_run, UNINSTALL_REINSTALL_STAGE, observed_at, reinstall_issue
            ),
            reinstall_issue,
        )

    def require_predecessor(self, predecessor_stage: str) -> LinuxCleanHostReleaseEvidenceRun:
        evidence_run = self.journal.load_evidence_run()
        predecessor = self.journal.load_stage_record(predecessor_stage)
        if predecessor is None or predecessor.status != "verified":
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence requires verified predecessor stage: "
                + predecessor_stage
            )
        assert_bound_installer_artifact_is_unchanged(evidence_run)
        return evidence_run

    def record_stage(
        self,
        evidence_run: LinuxCleanHostReleaseEvidenceRun,
        stage: str,
        status: str,
        recorded_at: str,
        details: Mapping[str, Any],
        c24_proof: Mapping[str, Any] | None,
        issue: Mapping[str, str] | None = None,
    ) -> LinuxCleanHostReleaseEvidenceStageRecord:
        if self.journal.load_stage_record(stage) is not None:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host release evidence stage was already recorded: " + stage
            )
        document: dict[str, Any] = {
            "schemaVersion": "v1",
            "evidenceKind": "linux-clean-host-release-stage",
            "runId": evidence_run.run_id,
            "releaseDeliveryPlanId": evidence_run.release_delivery_plan_id,
            "stage": stage,
            "status": status,
            "recordedAt": recorded_at,
            "releaseIdentity": release_identity_document(evidence_run),
            "details": dict(details),
        }
        if issue is not None:
            document["issue"] = dict(issue)
        evidence_path, evidence_sha256 = write_new_evidence_document(
            evidence_run.evidence_directory, stage, document
        )
        if c24_proof is not None:
            c24_proof = {
                **c24_proof,
                "evidence": {"uri": evidence_path.as_uri(), "sha256": evidence_sha256},
            }
        stage_record = LinuxCleanHostReleaseEvidenceStageRecord(
            stage, status, recorded_at, evidence_path, evidence_sha256, c24_proof
        )
        self.journal.record_new_stage(stage_record, details)
        return stage_record


def create_linux_clean_host_release_evidence_run(
    journal_path: Path,
    evidence_directory: Path,
    installer_artifact_path: Path,
    release_delivery_plans_document: Path,
    release_delivery_plan_id: str,
    run_id: str,
    runner_id: str,
    debian_package_identifier: str,
    product_installation_root: Path,
    product_data_root: Path,
    command_contract: LinuxCleanHostReleaseEvidenceCommandContract,
) -> LinuxCleanHostReleaseEvidenceRun:
    """Create one immutable run from exact C23, C48 and command inputs."""

    validate_new_run_inputs(
        journal_path,
        evidence_directory,
        installer_artifact_path,
        release_delivery_plans_document,
        product_installation_root,
        product_data_root,
        command_contract,
    )
    for value, name in (
        (run_id, "Linux clean-Host evidence run ID"),
        (runner_id, "Linux clean-Host runner ID"),
        (debian_package_identifier, "Linux DEB package identifier"),
    ):
        if not value:
            raise LinuxCleanHostReleaseEvidenceRunError(name + " is required")
    try:
        release_plan = load_selected_linux_host_deb_release_plan(
            release_delivery_plans_document, release_delivery_plan_id
        )
    except ProductDeliveryReleasePlanError as error:
        raise LinuxCleanHostReleaseEvidenceRunError(str(error)) from error
    if installer_artifact_path.name != release_plan.expected_deb_file_name:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host installer artifact file name must match C23 intended installer artifact"
        )
    evidence_run = evidence_run_from_release_plan(
        release_plan,
        installer_artifact_path,
        evidence_directory,
        run_id,
        runner_id,
        debian_package_identifier,
        product_installation_root,
        product_data_root,
        command_contract,
        utc_timestamp(),
    )
    LinuxCleanHostReleaseEvidenceJournal.create_new(journal_path, evidence_run)
    return evidence_run


def evidence_run_from_release_plan(
    release_plan: LinuxHostDEBReleasePlan,
    installer_artifact_path: Path,
    evidence_directory: Path,
    run_id: str,
    runner_id: str,
    debian_package_identifier: str,
    product_installation_root: Path,
    product_data_root: Path,
    command_contract: LinuxCleanHostReleaseEvidenceCommandContract,
    created_at: str,
) -> LinuxCleanHostReleaseEvidenceRun:
    return LinuxCleanHostReleaseEvidenceRun(
        run_id,
        runner_id,
        release_plan.release_delivery_plan_id,
        release_plan.product_version,
        release_plan.expected_deb_file_name,
        debian_package_identifier,
        release_plan.host_agent_systemd_service_name,
        release_plan.host_edge_proxy_systemd_service_name,
        release_plan.host_update_handoff_supervisor_systemd_service_name,
        product_installation_root,
        product_data_root,
        installer_artifact_path,
        sha256_file(installer_artifact_path),
        evidence_directory,
        command_contract,
        created_at,
    )


def evidence_run_document(evidence_run: LinuxCleanHostReleaseEvidenceRun) -> Mapping[str, Any]:
    return {
        "runId": evidence_run.run_id,
        "runnerId": evidence_run.runner_id,
        "releaseDeliveryPlanId": evidence_run.release_delivery_plan_id,
        "productVersion": evidence_run.product_version,
        "intendedInstallerFileName": evidence_run.intended_installer_file_name,
        "debianPackageIdentifier": evidence_run.debian_package_identifier,
        "hostAgentSystemdServiceName": evidence_run.host_agent_systemd_service_name,
        "hostEdgeProxySystemdServiceName": evidence_run.host_edge_proxy_systemd_service_name,
        "hostUpdateHandoffSupervisorSystemdServiceName": evidence_run.host_update_handoff_supervisor_systemd_service_name,
        "productInstallationRoot": str(evidence_run.product_installation_root),
        "productDataRoot": str(evidence_run.product_data_root),
        "installerArtifactPath": str(evidence_run.installer_artifact_path),
        "boundInstallerArtifactSHA256": evidence_run.bound_installer_artifact_sha256,
        "evidenceDirectory": str(evidence_run.evidence_directory),
        "commandContract": command_contract_document(evidence_run.command_contract),
        "createdAt": evidence_run.created_at,
    }


def evidence_run_from_document(document: Any) -> LinuxCleanHostReleaseEvidenceRun:
    if not isinstance(document, dict):
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host release evidence run must be an object"
        )
    return LinuxCleanHostReleaseEvidenceRun(
        required_string(document.get("runId"), "journal run ID"),
        required_string(document.get("runnerId"), "journal runner ID"),
        required_string(document.get("releaseDeliveryPlanId"), "journal C23 plan ID"),
        required_string(document.get("productVersion"), "journal product version"),
        required_string(document.get("intendedInstallerFileName"), "journal DEB file name"),
        required_string(document.get("debianPackageIdentifier"), "journal DEB package identifier"),
        required_string(document.get("hostAgentSystemdServiceName"), "journal Host Agent systemd name"),
        required_string(document.get("hostEdgeProxySystemdServiceName"), "journal Host Edge Proxy systemd name"),
        required_string(document.get("hostUpdateHandoffSupervisorSystemdServiceName"), "journal Handoff systemd name"),
        Path(required_string(document.get("productInstallationRoot"), "journal product root")),
        Path(required_string(document.get("productDataRoot"), "journal data root")),
        Path(required_string(document.get("installerArtifactPath"), "journal DEB path")),
        required_sha256(document.get("boundInstallerArtifactSHA256"), "journal DEB SHA-256"),
        Path(required_string(document.get("evidenceDirectory"), "journal evidence directory")),
        command_contract_from_document(document.get("commandContract")),
        required_string(document.get("createdAt"), "journal creation time"),
    )


def validate_new_run_inputs(
    journal_path: Path,
    evidence_directory: Path,
    installer_artifact_path: Path,
    release_delivery_plans_document: Path,
    product_installation_root: Path,
    product_data_root: Path,
    command_contract: LinuxCleanHostReleaseEvidenceCommandContract,
) -> None:
    if not journal_path.is_absolute() or not journal_path.parent.is_dir():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host evidence journal path must be absolute and have an existing parent directory"
        )
    if not evidence_directory.is_absolute() or not evidence_directory.is_dir():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host evidence directory must be an existing absolute directory"
        )
    if not installer_artifact_path.is_absolute() or not installer_artifact_path.is_file():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host installer artifact is missing or not an absolute file"
        )
    if not release_delivery_plans_document.is_absolute() or not release_delivery_plans_document.is_file():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "C23 release delivery plans document is missing or not an absolute file"
        )
    if not product_installation_root.is_absolute() or not product_data_root.is_absolute():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux product installation and data roots must be absolute paths"
        )
    for name, executable in (
        ("dpkg-deb", command_contract.dpkg_deb_executable),
        ("dpkg", command_contract.dpkg_executable),
        ("dpkg-query", command_contract.dpkg_query_executable),
        ("systemctl", command_contract.systemctl_executable),
        ("test", command_contract.test_executable),
        ("cat", command_contract.cat_executable),
    ):
        if not executable.is_absolute() or not executable.is_file():
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host " + name + " executable is missing or not an absolute file"
            )
    if not command_contract.boot_id_path.is_absolute():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host boot ID path must be absolute"
        )


def command_contract_document(
    command_contract: LinuxCleanHostReleaseEvidenceCommandContract,
) -> Mapping[str, str]:
    return {
        "dpkgDebExecutable": str(command_contract.dpkg_deb_executable),
        "dpkgExecutable": str(command_contract.dpkg_executable),
        "dpkgQueryExecutable": str(command_contract.dpkg_query_executable),
        "systemctlExecutable": str(command_contract.systemctl_executable),
        "testExecutable": str(command_contract.test_executable),
        "catExecutable": str(command_contract.cat_executable),
        "bootIdPath": str(command_contract.boot_id_path),
    }


def command_contract_from_document(
    document: Any,
) -> LinuxCleanHostReleaseEvidenceCommandContract:
    if not isinstance(document, dict):
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host release evidence command contract must be an object"
        )
    return LinuxCleanHostReleaseEvidenceCommandContract(
        Path(required_string(document.get("dpkgDebExecutable"), "journal dpkg-deb executable")),
        Path(required_string(document.get("dpkgExecutable"), "journal dpkg executable")),
        Path(required_string(document.get("dpkgQueryExecutable"), "journal dpkg-query executable")),
        Path(required_string(document.get("systemctlExecutable"), "journal systemctl executable")),
        Path(required_string(document.get("testExecutable"), "journal test executable")),
        Path(required_string(document.get("catExecutable"), "journal cat executable")),
        Path(required_string(document.get("bootIdPath"), "journal boot ID path")),
    )


def assert_bound_installer_artifact_is_unchanged(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
) -> None:
    if not evidence_run.installer_artifact_path.is_absolute() or not evidence_run.installer_artifact_path.is_file():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "bound Linux clean-Host installer artifact is missing or not a file"
        )
    if sha256_file(evidence_run.installer_artifact_path) != evidence_run.bound_installer_artifact_sha256:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "bound Linux clean-Host installer artifact SHA-256 changed after evidence run creation"
        )


def observed_installer_artifact(
    evidence_run: LinuxCleanHostReleaseEvidenceRun, observed_at: str
) -> Mapping[str, str]:
    assert_bound_installer_artifact_is_unchanged(evidence_run)
    return {
        "kind": "deb",
        "fileName": evidence_run.intended_installer_file_name,
        "productVersion": evidence_run.product_version,
        "sha256": evidence_run.bound_installer_artifact_sha256,
        "observedAt": observed_at,
    }


def execute_linux_clean_host_command(
    executable: Path, arguments: Sequence[str]
) -> linux_host_installation_observation.LinuxHostInstallationCommandObservation:
    try:
        return linux_host_installation_observation.execute_linux_host_installation_command(
            executable, arguments
        )
    except linux_host_installation_observation.LinuxHostInstallationObservationError as error:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host command execution failed: " + str(error)
        ) from error


def observe_linux_deb_artifact_release_identity(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
) -> linux_host_installation_observation.LinuxDEBArtifactIdentityObservation:
    return linux_host_installation_observation.observe_linux_deb_artifact_identity(
        evidence_run.command_contract.dpkg_deb_executable,
        evidence_run.installer_artifact_path,
        execute_command=execute_linux_clean_host_command,
    )


def observe_linux_deb_package_registration(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
) -> linux_host_installation_observation.LinuxDEBPackageRegistrationObservation:
    return linux_host_installation_observation.observe_linux_deb_package_registration(
        evidence_run.command_contract.dpkg_query_executable,
        evidence_run.debian_package_identifier,
        execute_command=execute_linux_clean_host_command,
    )


def observe_required_systemd_services(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
) -> list[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation]:
    return [
        linux_host_installation_observation.observe_linux_systemd_service_registration(
            evidence_run.command_contract.systemctl_executable,
            role,
            service_name,
            execute_command=execute_linux_clean_host_command,
        )
        for role, service_name in (
            ("host-agent", evidence_run.host_agent_systemd_service_name),
            ("host-edge-proxy", evidence_run.host_edge_proxy_systemd_service_name),
            ("host-update-handoff-supervisor", evidence_run.host_update_handoff_supervisor_systemd_service_name),
        )
    ]


def observe_required_roots(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
) -> list[linux_host_installation_observation.LinuxPathObservation]:
    return [
        linux_host_installation_observation.observe_linux_path(
            evidence_run.command_contract.test_executable,
            path,
            execute_command=execute_linux_clean_host_command,
        )
        for path in (evidence_run.product_installation_root, evidence_run.product_data_root)
    ]


def observe_linux_host_boot_session(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
) -> linux_host_installation_observation.LinuxHostBootSessionObservation:
    try:
        return linux_host_installation_observation.observe_linux_host_boot_session(
            evidence_run.command_contract.cat_executable,
            evidence_run.command_contract.boot_id_path,
            execute_command=execute_linux_clean_host_command,
        )
    except linux_host_installation_observation.LinuxHostInstallationObservationError as error:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host boot session identifier is unavailable: " + str(error)
        ) from error


def deb_artifact_integrity_issue(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    identity: linux_host_installation_observation.LinuxDEBArtifactIdentityObservation,
) -> Mapping[str, str] | None:
    if identity.state != "available":
        return {
            "code": "linux-deb-metadata-unavailable",
            "message": "dpkg-deb could not provide readable Package and Version metadata for the selected DEB.",
        }
    if identity.package_identifier != evidence_run.debian_package_identifier:
        return {
            "code": "linux-deb-package-identifier-mismatch",
            "message": "The observed DEB Package does not match the selected package identifier.",
        }
    if identity.product_version != evidence_run.product_version:
        return {
            "code": "linux-deb-product-version-mismatch",
            "message": "The observed DEB Version does not match C23.",
        }
    return None


def clean_host_preflight_issue(
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    roots: Sequence[linux_host_installation_observation.LinuxPathObservation],
) -> Mapping[str, str] | None:
    if registration.state != "absent":
        return {
            "code": "linux-clean-host-deb-package-not-absent",
            "message": "The selected Debian package was not explicitly observed as absent.",
        }
    for service in services:
        if service.state != "absent":
            return {
                "code": "linux-clean-host-systemd-service-not-absent",
                "message": "A C23-required systemd service was not explicitly observed as absent.",
            }
    for root in roots:
        if root.state != "absent":
            return {
                "code": "linux-clean-host-retained-root-not-absent",
                "message": "A declared product installation or data root was not explicitly observed as absent.",
            }
    return None


def clean_install_issue(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    installer_command: linux_host_installation_observation.LinuxHostInstallationCommandObservation,
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
) -> Mapping[str, str] | None:
    if installer_command.returncode != 0:
        return {
            "code": "linux-clean-install-command-failed",
            "message": "dpkg returned a non-zero result for the selected C23 DEB.",
        }
    return installed_deb_registration_issue(evidence_run, registration)


def installed_deb_registration_issue(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
) -> Mapping[str, str] | None:
    if registration.state != "installed":
        return {
            "code": "linux-installed-deb-registration-not-observed",
            "message": "dpkg did not explicitly report the selected DEB as install ok installed.",
        }
    if registration.product_version != evidence_run.product_version:
        return {
            "code": "linux-installed-deb-version-mismatch",
            "message": "The observed installed DEB version does not match C23.",
        }
    return None


def installed_receipt_or_service_registration_issue(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    roots: Sequence[linux_host_installation_observation.LinuxPathObservation],
) -> Mapping[str, str] | None:
    receipt_issue = installed_deb_registration_issue(evidence_run, registration)
    if receipt_issue is not None:
        return receipt_issue
    if any(service.state != "registered" for service in services):
        return {
            "code": "linux-systemd-service-registration-not-observed",
            "message": "A C23-required systemd service was not observed as loaded.",
        }
    if any(root.state != "present" for root in roots):
        return {
            "code": "linux-product-root-not-observed",
            "message": "A declared product installation or data root was not observed as present.",
        }
    return None


def reboot_persistence_issue(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    checkpoint: str,
    boot_session: linux_host_installation_observation.LinuxHostBootSessionObservation,
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    roots: Sequence[linux_host_installation_observation.LinuxPathObservation],
) -> Mapping[str, str] | None:
    if boot_session.boot_session_identifier == checkpoint:
        return {
            "code": "linux-reboot-not-observed",
            "message": "The Linux kernel boot-session identifier did not change after checkpoint.",
        }
    return installed_receipt_or_service_registration_issue(
        evidence_run, registration, services, roots
    )


def observe_host_platform_transition(
    stage: str,
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    release_delivery_plans_document: Path,
    host_update_journal_path: Path,
    host_platform_effect_receipt_path: Path,
    host_installation_manifest_path: Path,
    host_installation_footprint_path: Path,
) -> tuple[
    host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence | None,
    Mapping[str, str] | None,
]:
    """Read C29/C28/C55/C48/C49 without making it C24 success by itself."""

    release_plan_issue = transition_release_plan_issue(
        evidence_run, release_delivery_plans_document
    )
    if release_plan_issue is not None:
        return None, release_plan_issue
    try:
        if stage == UPDATE_STAGE:
            transition = (
                host_platform_release_transition_evidence.inspect_host_platform_update_transition(
                    release_delivery_plans_document,
                    evidence_run.release_delivery_plan_id,
                    host_update_journal_path,
                    host_platform_effect_receipt_path,
                    host_installation_manifest_path,
                    host_installation_footprint_path,
                )
            )
        elif stage == ROLLBACK_STAGE:
            transition = (
                host_platform_release_transition_evidence.inspect_host_platform_rollback_transition(
                    release_delivery_plans_document,
                    evidence_run.release_delivery_plan_id,
                    host_update_journal_path,
                    host_platform_effect_receipt_path,
                    host_installation_manifest_path,
                    host_installation_footprint_path,
                )
            )
        else:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux Host platform transition stage is unsupported: " + stage
            )
    except host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidenceError as error:
        return None, {
            "code": "linux-host-platform-" + stage + "-transition-invalid",
            "message": "C29/C28/C55/C48/C49 transition evidence is invalid: " + str(error),
        }
    if (
        transition.release_delivery_plan_id != evidence_run.release_delivery_plan_id
        or transition.platform != "linux"
        or transition.provider_kind != "linux-kvm-libvirt-systemd"
        or transition.target_product_version != evidence_run.product_version
        or transition.observed_package_identifier != evidence_run.debian_package_identifier
    ):
        return None, {
            "code": "linux-host-platform-" + stage + "-transition-identity-mismatch",
            "message": "C29/C28/C55/C48/C49 transition evidence does not match this Linux C24 evidence run.",
        }
    return transition, None


def transition_release_plan_issue(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    release_delivery_plans_document: Path,
) -> Mapping[str, str] | None:
    """Require the transition reader's C23 selection to equal this run's C23 facts."""

    try:
        release_plan = load_selected_linux_host_deb_release_plan(
            release_delivery_plans_document, evidence_run.release_delivery_plan_id
        )
    except ProductDeliveryReleasePlanError as error:
        return {
            "code": "linux-host-platform-transition-release-plan-unavailable",
            "message": "The explicit C23 document cannot be selected for this C24 run: " + str(error),
        }
    if (
        release_plan.product_version != evidence_run.product_version
        or release_plan.expected_deb_file_name != evidence_run.intended_installer_file_name
        or release_plan.host_agent_systemd_service_name
        != evidence_run.host_agent_systemd_service_name
        or release_plan.host_edge_proxy_systemd_service_name
        != evidence_run.host_edge_proxy_systemd_service_name
        or release_plan.host_update_handoff_supervisor_systemd_service_name
        != evidence_run.host_update_handoff_supervisor_systemd_service_name
    ):
        return {
            "code": "linux-host-platform-transition-release-plan-mismatch",
            "message": "The explicit C23 document does not preserve this run's selected DEB and systemd identities.",
        }
    return None


def host_platform_transition_os_issue(
    stage: str,
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    transition: host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence,
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    roots: Sequence[linux_host_installation_observation.LinuxPathObservation],
) -> Mapping[str, str] | None:
    """Require fresh OS observations to agree with the C48/C49 transition.

    A rollback may restore an older version, so it deliberately compares dpkg
    with the restored C48 version rather than the C23 target version.
    """

    if registration.state != "installed":
        return {
            "code": "linux-host-platform-" + stage + "-package-not-installed",
            "message": "dpkg did not explicitly report the Host Platform package as installed after the transition.",
        }
    if registration.product_version != transition.observed_product_version:
        return {
            "code": "linux-host-platform-" + stage + "-package-version-mismatch",
            "message": "The fresh dpkg product version does not match the C48/C49 transition observation.",
        }
    if any(service.state != "registered" for service in services):
        return {
            "code": "linux-host-platform-" + stage + "-service-registration-not-observed",
            "message": "A required systemd service was not registered after the Host Platform transition.",
        }
    if any(root.state != "present" for root in roots):
        return {
            "code": "linux-host-platform-" + stage + "-root-not-observed",
            "message": "A declared product root was not present after the Host Platform transition.",
        }
    if stage == UPDATE_STAGE and registration.product_version != evidence_run.product_version:
        return {
            "code": "linux-host-platform-update-target-version-mismatch",
            "message": "The successful update did not leave the C23 target product version installed.",
        }
    return None


def observe_completed_linux_preservation_removal_receipt(
    receipt_path: Path,
    expected_installation_id: str,
    expected_release_id: str,
) -> tuple[Mapping[str, Any] | None, str | None, Mapping[str, str] | None]:
    """Read the C54 receipt without turning absence into product removal."""

    if not expected_installation_id or not expected_release_id:
        return None, None, {
            "code": "linux-removal-receipt-identity-not-declared",
            "message": "The C54 installation and release identities must be explicit.",
        }
    if not receipt_path.is_absolute() or receipt_path.is_symlink() or not receipt_path.is_file():
        return None, None, {
            "code": "linux-removal-receipt-unavailable",
            "message": "The C54 removal receipt must be one absolute regular non-symlink file.",
        }
    try:
        payload = receipt_path.read_bytes()
        receipt = json.loads(payload)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return None, None, {
            "code": "linux-removal-receipt-unreadable",
            "message": "The C54 removal receipt could not be decoded: " + str(error),
        }
    if not isinstance(receipt, dict):
        return None, None, {
            "code": "linux-removal-receipt-invalid",
            "message": "The C54 removal receipt must contain one JSON object.",
        }
    if (
        receipt.get("schemaVersion") != "v1"
        or receipt.get("documentKind") != "host-product-removal-receipt"
        or receipt.get("state") != "completed"
        or receipt.get("dataDisposition") != "preserve-mutable-data"
        or receipt.get("packageReceiptRemoval") != "removed-by-os-package-manager"
        or receipt.get("installationId") != expected_installation_id
        or receipt.get("releaseId") != expected_release_id
    ):
        return None, None, {
            "code": "linux-removal-receipt-does-not-prove-preserving-completion",
            "message": "The C54 receipt does not match the declared completed Linux preservation removal.",
        }
    for field in ("id", "requestId", "observedAt"):
        if not isinstance(receipt.get(field), str) or not receipt[field]:
            return None, None, {
                "code": "linux-removal-receipt-invalid",
                "message": "The C54 receipt is missing required field " + field + ".",
            }
    retained = receipt.get("retainedMutableStoreIds")
    if retained is not None and (
        not isinstance(retained, list)
        or any(not isinstance(item, str) or not item for item in retained)
        or len(set(retained)) != len(retained)
    ):
        return None, None, {
            "code": "linux-removal-receipt-invalid",
            "message": "The C54 receipt retained mutable store IDs are invalid.",
        }
    return receipt, hashlib.sha256(payload).hexdigest(), None


def uninstall_preserving_data_issue(
    removal_command: linux_host_installation_observation.LinuxHostInstallationCommandObservation,
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    roots: Sequence[linux_host_installation_observation.LinuxPathObservation],
    removal_receipt_issue: Mapping[str, str] | None,
) -> Mapping[str, str] | None:
    if removal_command.returncode != 0:
        return {
            "code": "linux-uninstall-command-failed",
            "message": "dpkg returned a non-zero result for the explicit package removal.",
        }
    if removal_receipt_issue is not None:
        return removal_receipt_issue
    if registration.state != "absent":
        return {
            "code": "linux-uninstall-package-receipt-not-absent",
            "message": "dpkg did not explicitly report the removed package as absent/configuration-retained.",
        }
    if any(service.state != "absent" for service in services):
        return {
            "code": "linux-uninstall-service-registration-remains",
            "message": "A C23-required systemd service remained registered after removal.",
        }
    if len(roots) != 2 or roots[0].state != "absent" or roots[1].state != "present":
        return {
            "code": "linux-uninstall-preservation-state-not-observed",
            "message": "Removal did not explicitly leave immutable product content absent and mutable data present.",
        }
    return None


def reinstall_after_preserving_removal_issue(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    reinstall_command: linux_host_installation_observation.LinuxHostInstallationCommandObservation,
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    roots: Sequence[linux_host_installation_observation.LinuxPathObservation],
) -> Mapping[str, str] | None:
    if reinstall_command.returncode != 0:
        return {
            "code": "linux-reinstall-command-failed",
            "message": "dpkg returned a non-zero result for explicit reinstallation.",
        }
    return installed_receipt_or_service_registration_issue(
        evidence_run, registration, services, roots
    )


def observation_details(
    registration: linux_host_installation_observation.LinuxDEBPackageRegistrationObservation,
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    roots: Sequence[linux_host_installation_observation.LinuxPathObservation],
) -> Mapping[str, Any]:
    return {
        "debPackageRegistrationObservation": linux_host_installation_observation.deb_package_registration_document(registration),
        "systemdServiceRegistrationObservations": [
            linux_host_installation_observation.systemd_service_registration_document(service)
            for service in services
        ],
        "productRootObservations": [
            linux_host_installation_observation.path_document(root) for root in roots
        ],
    }


def compose_verified_c24_proof(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    stage: str,
    recorded_at: str,
    artifact: Mapping[str, str],
    optional_stage_observation: Any | None = None,
) -> Mapping[str, Any]:
    proof: dict[str, Any] = {
        "planId": evidence_run.release_delivery_plan_id,
        "platform": "linux",
        "providerKind": "linux-kvm-libvirt-systemd",
        "stage": stage,
        "status": "verified",
        "recordedAt": recorded_at,
        "runner": {"kind": "linux-clean-host", "id": evidence_run.runner_id},
        "observedInstallerArtifact": dict(artifact),
    }
    if stage == SERVICE_REGISTRATION_STAGE:
        proof["observedHostServiceRegistrations"] = optional_stage_observation
    return proof


def compose_failed_c24_proof(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
    stage: str,
    recorded_at: str,
    issue: Mapping[str, str],
) -> Mapping[str, Any]:
    return {
        "planId": evidence_run.release_delivery_plan_id,
        "platform": "linux",
        "providerKind": "linux-kvm-libvirt-systemd",
        "stage": stage,
        "status": "failed",
        "recordedAt": recorded_at,
        "runner": {"kind": "linux-clean-host", "id": evidence_run.runner_id},
        "issue": dict(issue),
    }


def observed_host_service_registrations(
    services: Sequence[linux_host_installation_observation.LinuxSystemdServiceRegistrationObservation],
    observed_at: str,
) -> list[Mapping[str, str]]:
    registrations: list[Mapping[str, str]] = []
    for service in services:
        if service.state != "registered":
            raise LinuxCleanHostReleaseEvidenceRunError(
                "cannot compose an observed systemd service registration from " + service.state
            )
        registrations.append(
            {
                "role": service.role,
                "manager": "systemd",
                "name": service.service_name,
                "registrationState": "registered",
                "observedAt": observed_at,
            }
        )
    return registrations


def release_identity_document(
    evidence_run: LinuxCleanHostReleaseEvidenceRun,
) -> Mapping[str, str]:
    return {
        "productVersion": evidence_run.product_version,
        "intendedInstallerFileName": evidence_run.intended_installer_file_name,
        "debianPackageIdentifier": evidence_run.debian_package_identifier,
        "hostAgentSystemdServiceName": evidence_run.host_agent_systemd_service_name,
        "hostEdgeProxySystemdServiceName": evidence_run.host_edge_proxy_systemd_service_name,
        "hostUpdateHandoffSupervisorSystemdServiceName": evidence_run.host_update_handoff_supervisor_systemd_service_name,
        "productInstallationRoot": str(evidence_run.product_installation_root),
        "productDataRoot": str(evidence_run.product_data_root),
        "boundInstallerArtifactSHA256": evidence_run.bound_installer_artifact_sha256,
    }


def boot_session_identifier_from_checkpoint(details: Mapping[str, Any]) -> str:
    observation = details.get("bootSessionObservation")
    if not isinstance(observation, dict):
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux reboot checkpoint does not contain a boot-session observation"
        )
    return required_string(
        observation.get("bootSessionIdentifier"), "Linux reboot checkpoint boot-session identifier"
    )


def write_new_evidence_document(
    evidence_directory: Path, stage: str, document: Mapping[str, Any]
) -> tuple[Path, str]:
    validate_release_evidence_stage(stage)
    evidence_path = evidence_directory / (stage + ".json")
    if evidence_path.exists():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host evidence document already exists for stage: " + stage
        )
    bytes_value = (canonical_json(document) + "\n").encode("utf-8")
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=evidence_directory, prefix="." + stage + ".", delete=False
        ) as temporary_file:
            temporary_file.write(bytes_value)
            temporary_path = Path(temporary_file.name)
        os.replace(temporary_path, evidence_path)
    except OSError as error:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host evidence document write failed: " + str(error)
        ) from error
    return evidence_path, sha256_file(evidence_path)


def write_new_c24_proof_fragment(
    output_proof_fragment_path: Path,
    stage_record: LinuxCleanHostReleaseEvidenceStageRecord,
) -> tuple[Path, str]:
    """Write one immutable C24 fragment from runner-owned journal state."""

    if stage_record.c24_proof is None:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host release evidence stage has no C24 proof: "
            + stage_record.stage
        )
    if not output_proof_fragment_path.is_absolute():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux C24 proof fragment output path must be absolute"
        )
    if not output_proof_fragment_path.parent.is_dir():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux C24 proof fragment output parent directory is missing: "
            + str(output_proof_fragment_path.parent)
        )
    if output_proof_fragment_path.exists() or output_proof_fragment_path.is_symlink():
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux C24 proof fragment output already exists: "
            + str(output_proof_fragment_path)
        )
    document_bytes = (
        canonical_json({"schemaVersion": "v1", "proofs": [stage_record.c24_proof]})
        + "\n"
    ).encode("utf-8")
    try:
        with output_proof_fragment_path.open("xb") as output_file:
            output_file.write(document_bytes)
            output_file.flush()
            os.fsync(output_file.fileno())
    except FileExistsError as error:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux C24 proof fragment output already exists: "
            + str(output_proof_fragment_path)
        ) from error
    except OSError as error:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux C24 proof fragment write failed: " + str(error)
        ) from error
    return output_proof_fragment_path, sha256_file(output_proof_fragment_path)


def stage_record_document(
    stage_record: LinuxCleanHostReleaseEvidenceStageRecord,
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
        raise LinuxCleanHostReleaseEvidenceRunError(
            "unknown Linux clean-Host release evidence stage: " + stage
        )


def required_string(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise LinuxCleanHostReleaseEvidenceRunError(name + " must be a non-empty string")
    return value


def required_sha256(value: Any, name: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise LinuxCleanHostReleaseEvidenceRunError(name + " must be a lowercase SHA-256")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host file digest read failed: " + str(error)
        ) from error
    return digest.hexdigest()


def canonical_json(document: Any) -> str:
    return json.dumps(document, sort_keys=True, separators=(",", ":"))


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def require_linux_host_platform() -> None:
    if platform.system() != "Linux":
        raise LinuxCleanHostReleaseEvidenceRunError(
            "Linux clean-Host release evidence CLI requires a Linux Host"
        )


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    create = subparsers.add_parser("create-run")
    create.add_argument("--journal", required=True, type=Path)
    create.add_argument("--evidence-directory", required=True, type=Path)
    create.add_argument("--installer-artifact", required=True, type=Path)
    create.add_argument("--release-delivery-plans-document", required=True, type=Path)
    create.add_argument("--release-delivery-plan-id", required=True)
    create.add_argument("--run-id", required=True)
    create.add_argument("--runner-id", required=True)
    create.add_argument("--debian-package-identifier", required=True)
    create.add_argument("--product-installation-root", required=True, type=Path)
    create.add_argument("--product-data-root", required=True, type=Path)
    for name in ("dpkg-deb", "dpkg", "dpkg-query", "systemctl", "test", "cat"):
        create.add_argument("--" + name + "-executable", required=True, type=Path)
    create.add_argument("--boot-id-path", required=True, type=Path)
    for operation in (
        "record-artifact-integrity",
        "record-clean-host-preflight",
        "record-service-registration",
        "record-reboot-checkpoint",
        "record-reboot",
    ):
        parser_for_operation = subparsers.add_parser(operation)
        parser_for_operation.add_argument("--journal", required=True, type=Path)
    write_fragment = subparsers.add_parser("write-stage-proof-fragment")
    write_fragment.add_argument("--journal", required=True, type=Path)
    write_fragment.add_argument("--stage", required=True, choices=C24_PROOF_STAGES)
    write_fragment.add_argument("--output-proof-fragment", required=True, type=Path)
    clean_install = subparsers.add_parser("execute-clean-install")
    clean_install.add_argument("--journal", required=True, type=Path)
    clean_install.add_argument(
        "--authorize-clean-install",
        action="store_true",
        help="explicitly authorize the privileged DEB installation effect",
    )
    for operation in ("record-host-platform-update", "record-host-platform-rollback"):
        parser_for_operation = subparsers.add_parser(operation)
        parser_for_operation.add_argument("--journal", required=True, type=Path)
        parser_for_operation.add_argument("--release-delivery-plans-document", required=True, type=Path)
        parser_for_operation.add_argument("--host-update-journal", required=True, type=Path)
        parser_for_operation.add_argument("--host-platform-effect-receipt", required=True, type=Path)
        parser_for_operation.add_argument("--host-installation-manifest", required=True, type=Path)
        parser_for_operation.add_argument("--host-installation-footprint", required=True, type=Path)
    uninstall_reinstall = subparsers.add_parser(
        "execute-uninstall-reinstall-preserving-data"
    )
    uninstall_reinstall.add_argument("--journal", required=True, type=Path)
    uninstall_reinstall.add_argument("--removal-receipt", required=True, type=Path)
    uninstall_reinstall.add_argument("--expected-removal-installation-id", required=True)
    uninstall_reinstall.add_argument("--expected-removal-release-id", required=True)
    uninstall_reinstall.add_argument(
        "--authorize-uninstall-reinstall",
        action="store_true",
        help="explicitly authorize the privileged DEB removal and reinstall effects",
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        require_linux_host_platform()
        if parsed.operation == "create-run":
            evidence_run = create_linux_clean_host_release_evidence_run(
                parsed.journal,
                parsed.evidence_directory,
                parsed.installer_artifact,
                parsed.release_delivery_plans_document,
                parsed.release_delivery_plan_id,
                parsed.run_id,
                parsed.runner_id,
                parsed.debian_package_identifier,
                parsed.product_installation_root,
                parsed.product_data_root,
                LinuxCleanHostReleaseEvidenceCommandContract(
                    parsed.dpkg_deb_executable,
                    parsed.dpkg_executable,
                    parsed.dpkg_query_executable,
                    parsed.systemctl_executable,
                    parsed.test_executable,
                    parsed.cat_executable,
                    parsed.boot_id_path,
                ),
            )
            print(canonical_json({"evidenceRun": evidence_run_document(evidence_run)}))
            return 0
        if parsed.operation == "execute-clean-install" and not parsed.authorize_clean_install:
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host installation requires --authorize-clean-install"
            )
        if (
            parsed.operation == "execute-uninstall-reinstall-preserving-data"
            and not parsed.authorize_uninstall_reinstall
        ):
            raise LinuxCleanHostReleaseEvidenceRunError(
                "Linux clean-Host preservation removal and reinstall require --authorize-uninstall-reinstall"
            )
        runner = LinuxCleanHostReleaseEvidenceRunner(
            LinuxCleanHostReleaseEvidenceJournal(parsed.journal)
        )
        if parsed.operation == "write-stage-proof-fragment":
            stage_record = runner.journal.load_stage_record(parsed.stage)
            if stage_record is None:
                raise LinuxCleanHostReleaseEvidenceRunError(
                    "Linux clean-Host release evidence stage has no C24 proof: "
                    + parsed.stage
                )
            output_path, output_sha256 = write_new_c24_proof_fragment(
                parsed.output_proof_fragment, stage_record
            )
            print(
                canonical_json(
                    {
                        "proofFragmentPath": str(output_path),
                        "proofFragmentSHA256": output_sha256,
                    }
                )
            )
            return 0
        actions = {
            "record-artifact-integrity": runner.record_artifact_integrity,
            "record-clean-host-preflight": runner.record_clean_host_preflight,
            "execute-clean-install": runner.execute_clean_install,
            "record-service-registration": runner.record_service_registration,
            "record-reboot-checkpoint": runner.record_reboot_checkpoint,
            "record-reboot": runner.record_reboot,
        }
        if parsed.operation == "execute-uninstall-reinstall-preserving-data":
            print(
                canonical_json(
                    stage_record_document(
                        runner.execute_uninstall_reinstall_preserving_data(
                            parsed.removal_receipt,
                            parsed.expected_removal_installation_id,
                            parsed.expected_removal_release_id,
                        )
                    )
                )
            )
            return 0
        if parsed.operation in {"record-host-platform-update", "record-host-platform-rollback"}:
            record_transition = (
                runner.record_host_platform_update
                if parsed.operation == "record-host-platform-update"
                else runner.record_host_platform_rollback
            )
            print(
                canonical_json(
                    stage_record_document(
                        record_transition(
                            parsed.release_delivery_plans_document,
                            parsed.host_update_journal,
                            parsed.host_platform_effect_receipt,
                            parsed.host_installation_manifest,
                            parsed.host_installation_footprint,
                        )
                    )
                )
            )
            return 0
        print(canonical_json(stage_record_document(actions[parsed.operation]())))
        return 0
    except LinuxCleanHostReleaseEvidenceRunError as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
