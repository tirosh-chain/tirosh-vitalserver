#!/usr/bin/env python3
"""Collect explicit Windows clean-Host C24 release-delivery evidence.

The runner owns one ``WindowsCleanHostReleaseEvidenceRun`` and its SQLite
journal.  Windows Installer, registry, SCM, filesystem, and boot-session facts
remain owned by Windows and are observed only through the declared command
contract in ``windows_host_installation_observation``.  A missing receipt,
ambiguous command error, changed MSI, or residual product root never becomes a
clean-Host claim by fallback.

The command that performs ``msiexec /i`` is intentionally separate from every
observation command.  Creating a run, inspecting integrity, and recording a
preflight cannot install software.  An elevated release operator must invoke
``execute-clean-install`` explicitly; the runner never reboots the Host.
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
from tooling import windows_host_installation_observation
from tooling.product_delivery_release_plan import (
    ProductDeliveryReleasePlanError,
    WindowsHostMSIReleasePlan,
    load_selected_windows_host_msi_release_plan,
)


class WindowsCleanHostReleaseEvidenceRunError(RuntimeError):
    """A Windows C24 evidence state is unavailable, invalid, or unsafe."""


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
class WindowsCleanHostReleaseEvidenceCommandContract:
    """Explicit Windows executables through which C24 facts are observed."""

    powershell_executable: Path
    msiexec_executable: Path
    registry_executable: Path
    sc_executable: Path


@dataclass(frozen=True)
class WindowsCleanHostReleaseEvidenceRun:
    """Release-process-owned immutable identity for one Windows evidence run."""

    run_id: str
    runner_id: str
    release_delivery_plan_id: str
    product_version: str
    intended_installer_file_name: str
    msi_product_code: str
    host_agent_windows_scm_service_name: str
    host_edge_proxy_windows_scm_service_name: str
    host_update_handoff_supervisor_windows_scm_service_name: str
    product_installation_root: Path
    product_immutable_release_root: Path
    product_data_root: Path
    installer_artifact_path: Path
    bound_installer_artifact_sha256: str
    evidence_directory: Path
    command_contract: WindowsCleanHostReleaseEvidenceCommandContract
    created_at: str


@dataclass(frozen=True)
class WindowsCleanHostReleaseEvidenceStageRecord:
    stage: str
    status: str
    recorded_at: str
    evidence_path: Path
    evidence_sha256: str
    c24_proof: Mapping[str, Any] | None


class WindowsCleanHostReleaseEvidenceJournal:
    """SQLite owner for one Windows clean-Host evidence run and its stages.

    This is deliberately not Host Agent state.  Release evidence has its own
    identity, transition rules, and retention policy, so it must not share a
    Host lifecycle database.
    """

    def __init__(self, journal_path: Path):
        self.journal_path = journal_path

    @classmethod
    def create_new(
        cls, journal_path: Path, evidence_run: WindowsCleanHostReleaseEvidenceRun
    ) -> "WindowsCleanHostReleaseEvidenceJournal":
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
                        msi_product_code TEXT NOT NULL,
                        host_agent_windows_scm_service_name TEXT NOT NULL,
                        host_edge_proxy_windows_scm_service_name TEXT NOT NULL,
                        host_update_handoff_supervisor_windows_scm_service_name TEXT NOT NULL,
                        product_installation_root TEXT NOT NULL,
                        product_immutable_release_root TEXT NOT NULL,
                        product_data_root TEXT NOT NULL,
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
                        msi_product_code, host_agent_windows_scm_service_name,
                        host_edge_proxy_windows_scm_service_name,
                        host_update_handoff_supervisor_windows_scm_service_name,
                        product_installation_root, product_immutable_release_root,
                        product_data_root, installer_artifact_path,
                        bound_installer_artifact_sha256, evidence_directory,
                        command_contract_json, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        evidence_run.run_id,
                        evidence_run.runner_id,
                        evidence_run.release_delivery_plan_id,
                        evidence_run.product_version,
                        evidence_run.intended_installer_file_name,
                        evidence_run.msi_product_code,
                        evidence_run.host_agent_windows_scm_service_name,
                        evidence_run.host_edge_proxy_windows_scm_service_name,
                        evidence_run.host_update_handoff_supervisor_windows_scm_service_name,
                        str(evidence_run.product_installation_root),
                        str(evidence_run.product_immutable_release_root),
                        str(evidence_run.product_data_root),
                        str(evidence_run.installer_artifact_path),
                        evidence_run.bound_installer_artifact_sha256,
                        str(evidence_run.evidence_directory),
                        canonical_json(command_contract_document(evidence_run.command_contract)),
                        evidence_run.created_at,
                    ),
                )
        except sqlite3.Error as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence journal create failed: " + str(error)
            ) from error
        return journal

    def load_evidence_run(self) -> WindowsCleanHostReleaseEvidenceRun:
        connection = self.open_existing_connection()
        try:
            row = connection.execute("SELECT * FROM evidence_run").fetchone()
        except sqlite3.Error as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence journal read failed: " + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence journal has no evidence run"
            )
        try:
            command_contract = command_contract_from_journal_document(
                json.loads(row["command_contract_json"])
            )
        except (TypeError, json.JSONDecodeError) as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence command contract is unreadable"
            ) from error
        return WindowsCleanHostReleaseEvidenceRun(
            run_id=required_non_empty_string(row["run_id"], "journal run ID"),
            runner_id=required_non_empty_string(row["runner_id"], "journal runner ID"),
            release_delivery_plan_id=required_non_empty_string(
                row["release_delivery_plan_id"], "journal C23 release delivery plan ID"
            ),
            product_version=required_non_empty_string(
                row["product_version"], "journal product version"
            ),
            intended_installer_file_name=required_non_empty_string(
                row["intended_installer_file_name"], "journal intended MSI file name"
            ),
            msi_product_code=required_non_empty_string(
                row["msi_product_code"], "journal MSI ProductCode"
            ),
            host_agent_windows_scm_service_name=required_non_empty_string(
                row["host_agent_windows_scm_service_name"], "journal Host Agent SCM name"
            ),
            host_edge_proxy_windows_scm_service_name=required_non_empty_string(
                row["host_edge_proxy_windows_scm_service_name"], "journal Host Edge Proxy SCM name"
            ),
            host_update_handoff_supervisor_windows_scm_service_name=required_non_empty_string(
                row["host_update_handoff_supervisor_windows_scm_service_name"],
                "journal Host Update Handoff Supervisor SCM name",
            ),
            product_installation_root=Path(
                required_non_empty_string(
                    row["product_installation_root"], "journal product installation root"
                )
            ),
            product_immutable_release_root=Path(
                required_non_empty_string(
                    row["product_immutable_release_root"],
                    "journal product immutable release root",
                )
            ),
            product_data_root=Path(
                required_non_empty_string(
                    row["product_data_root"], "journal product data root"
                )
            ),
            installer_artifact_path=Path(
                required_non_empty_string(
                    row["installer_artifact_path"], "journal MSI path"
                )
            ),
            bound_installer_artifact_sha256=required_sha256(
                row["bound_installer_artifact_sha256"], "journal MSI SHA-256"
            ),
            evidence_directory=Path(
                required_non_empty_string(
                    row["evidence_directory"], "journal evidence directory"
                )
            ),
            command_contract=command_contract,
            created_at=required_non_empty_string(row["created_at"], "journal creation time"),
        )

    def load_stage_record(
        self, stage: str
    ) -> WindowsCleanHostReleaseEvidenceStageRecord | None:
        validate_release_evidence_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT * FROM evidence_stage WHERE stage = ?", (stage,)
            ).fetchone()
        except sqlite3.Error as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage read failed: " + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            return None
        try:
            c24_proof = (
                json.loads(row["c24_proof_json"])
                if row["c24_proof_json"] is not None
                else None
            )
        except (TypeError, json.JSONDecodeError) as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence C24 proof is unreadable"
            ) from error
        if c24_proof is not None and not isinstance(c24_proof, dict):
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence C24 proof must be an object"
            )
        return WindowsCleanHostReleaseEvidenceStageRecord(
            stage=stage,
            status=required_non_empty_string(row["status"], "journal stage status"),
            recorded_at=required_non_empty_string(
                row["recorded_at"], "journal stage recorded time"
            ),
            evidence_path=Path(
                required_non_empty_string(row["evidence_path"], "journal evidence path")
            ),
            evidence_sha256=required_sha256(
                row["evidence_sha256"], "journal evidence SHA-256"
            ),
            c24_proof=c24_proof,
        )

    def load_stage_details(self, stage: str) -> Mapping[str, Any]:
        validate_release_evidence_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT details_json FROM evidence_stage WHERE stage = ?", (stage,)
            ).fetchone()
        except sqlite3.Error as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage details read failed: " + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage is not recorded: " + stage
            )
        try:
            details = json.loads(row["details_json"])
        except (TypeError, json.JSONDecodeError) as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage details are unreadable"
            ) from error
        if not isinstance(details, dict):
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage details must be an object"
            )
        return details

    def record_new_stage(
        self,
        stage_record: WindowsCleanHostReleaseEvidenceStageRecord,
        details: Mapping[str, Any],
    ) -> None:
        validate_release_evidence_stage(stage_record.stage)
        if stage_record.status not in {"verified", "failed"}:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage status must be verified or failed"
            )
        connection = self.open_existing_connection()
        try:
            existing = connection.execute(
                "SELECT stage FROM evidence_stage WHERE stage = ?", (stage_record.stage,)
            ).fetchone()
            if existing is not None:
                raise WindowsCleanHostReleaseEvidenceRunError(
                    "Windows clean-Host release evidence stage was already recorded: "
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
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage write failed: " + str(error)
            ) from error
        finally:
            connection.close()

    def open_existing_connection(self) -> sqlite3.Connection:
        if not self.journal_path.is_absolute() or not self.journal_path.is_file():
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence journal is missing or not a file"
            )
        try:
            connection = sqlite3.connect(self.journal_path)
            connection.row_factory = sqlite3.Row
            columns = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(evidence_run)")
            }
        except sqlite3.Error as error:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence journal open failed: " + str(error)
            ) from error
        required_columns = {
            "run_id",
            "msi_product_code",
            "host_update_handoff_supervisor_windows_scm_service_name",
            "product_installation_root",
            "product_immutable_release_root",
            "product_data_root",
            "command_contract_json",
        }
        if not required_columns.issubset(columns):
            connection.close()
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence journal does not record the "
                "C23 Windows MSI/SCM release identity"
            )
        return connection


class WindowsCleanHostReleaseEvidenceRunner:
    """Application workflow for explicit Windows C24 evidence transitions."""

    def __init__(self, journal: WindowsCleanHostReleaseEvidenceJournal):
        self.journal = journal

    def record_artifact_integrity(self) -> WindowsCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.journal.load_evidence_run()
        observed_at = utc_timestamp()
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        identity = observe_windows_msi_artifact_release_identity(
            evidence_run.command_contract.powershell_executable,
            evidence_run.installer_artifact_path,
        )
        issue = windows_msi_artifact_integrity_issue(evidence_run, identity)
        details = {
            "observedInstallerArtifact": observed_artifact,
            "msiArtifactIdentityObservation": windows_host_installation_observation.msi_artifact_identity_document(identity),
        }
        return self.record_stage_with_c24_proof(
            evidence_run,
            ARTIFACT_INTEGRITY_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            compose_verified_c24_proof(
                evidence_run, ARTIFACT_INTEGRITY_STAGE, observed_at, observed_artifact
            )
            if issue is None
            else compose_failed_c24_proof(
                evidence_run, ARTIFACT_INTEGRITY_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_clean_host_preflight(self) -> WindowsCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(ARTIFACT_INTEGRITY_STAGE)
        observed_at = utc_timestamp()
        msi_registration = observe_windows_msi_registration(evidence_run)
        service_observations = observe_required_windows_scm_service_registrations(
            evidence_run
        )
        product_root_state, product_root_command = observe_product_root_state(evidence_run)
        issue = clean_host_preflight_issue(
            msi_registration, service_observations, product_root_state
        )
        return self.record_stage_with_c24_proof(
            evidence_run,
            CLEAN_HOST_PREFLIGHT_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                "msiRegistrationObservation": windows_host_installation_observation.msi_registration_document(msi_registration),
                "scmServiceRegistrationObservations": [
                    windows_host_installation_observation.scm_service_registration_document(observation)
                    for observation in service_observations
                ],
                "productInstallationRootState": product_root_state,
                "productInstallationRootCommand": windows_host_installation_observation.command_document(product_root_command),
            },
            None,
            issue,
        )

    def execute_clean_install(self) -> WindowsCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(CLEAN_HOST_PREFLIGHT_STAGE)
        observed_at = utc_timestamp()
        installer_command = execute_windows_clean_host_command(
            evidence_run.command_contract.msiexec_executable,
            ["/i", str(evidence_run.installer_artifact_path), "/qn", "/norestart"],
        )
        msi_registration = observe_windows_msi_registration(evidence_run)
        issue = clean_install_issue(evidence_run, installer_command, msi_registration)
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        return self.record_stage_with_c24_proof(
            evidence_run,
            CLEAN_INSTALL_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                "installerCommand": windows_host_installation_observation.command_document(installer_command),
                "msiRegistrationObservation": windows_host_installation_observation.msi_registration_document(msi_registration),
                "observedInstallerArtifact": observed_artifact,
            },
            compose_verified_c24_proof(
                evidence_run, CLEAN_INSTALL_STAGE, observed_at, observed_artifact
            )
            if issue is None
            else compose_failed_c24_proof(
                evidence_run, CLEAN_INSTALL_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_service_registration(self) -> WindowsCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(CLEAN_INSTALL_STAGE)
        observed_at = utc_timestamp()
        msi_registration = observe_windows_msi_registration(evidence_run)
        service_observations = observe_required_windows_scm_service_registrations(
            evidence_run
        )
        product_root_state, product_root_command = observe_product_root_state(evidence_run)
        issue = installed_receipt_or_service_registration_issue(
            evidence_run, msi_registration, service_observations, product_root_state
        )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        return self.record_stage_with_c24_proof(
            evidence_run,
            SERVICE_REGISTRATION_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                "msiRegistrationObservation": windows_host_installation_observation.msi_registration_document(msi_registration),
                "scmServiceRegistrationObservations": [
                    windows_host_installation_observation.scm_service_registration_document(observation)
                    for observation in service_observations
                ],
                "productInstallationRootState": product_root_state,
                "productInstallationRootCommand": windows_host_installation_observation.command_document(product_root_command),
                "observedInstallerArtifact": observed_artifact,
            },
            compose_verified_c24_proof(
                evidence_run,
                SERVICE_REGISTRATION_STAGE,
                observed_at,
                observed_artifact,
                observed_host_service_registrations(service_observations, observed_at),
            )
            if issue is None
            else compose_failed_c24_proof(
                evidence_run, SERVICE_REGISTRATION_STAGE, observed_at, issue
            ),
            issue,
        )

    def record_reboot_checkpoint(self) -> WindowsCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(SERVICE_REGISTRATION_STAGE)
        observed_at = utc_timestamp()
        boot_session = observe_windows_host_boot_session(
            evidence_run.command_contract.powershell_executable
        )
        return self.record_stage_with_c24_proof(
            evidence_run,
            REBOOT_CHECKPOINT_STAGE,
            "verified",
            observed_at,
            {"bootSessionObservation": windows_host_installation_observation.boot_session_document(boot_session)},
            None,
        )

    def record_reboot(self) -> WindowsCleanHostReleaseEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(REBOOT_CHECKPOINT_STAGE)
        checkpoint_identifier = boot_session_identifier_from_checkpoint(
            self.journal.load_stage_details(REBOOT_CHECKPOINT_STAGE)
        )
        observed_at = utc_timestamp()
        current_boot_session = observe_windows_host_boot_session(
            evidence_run.command_contract.powershell_executable
        )
        msi_registration = observe_windows_msi_registration(evidence_run)
        service_observations = observe_required_windows_scm_service_registrations(
            evidence_run
        )
        product_root_state, product_root_command = observe_product_root_state(evidence_run)
        issue = reboot_persistence_issue(
            evidence_run,
            checkpoint_identifier,
            current_boot_session,
            msi_registration,
            service_observations,
            product_root_state,
        )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        return self.record_stage_with_c24_proof(
            evidence_run,
            REBOOT_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            {
                "preRebootBootSessionIdentifier": checkpoint_identifier,
                "postRebootBootSessionObservation": windows_host_installation_observation.boot_session_document(current_boot_session),
                "msiRegistrationObservation": windows_host_installation_observation.msi_registration_document(msi_registration),
                "scmServiceRegistrationObservations": [
                    windows_host_installation_observation.scm_service_registration_document(observation)
                    for observation in service_observations
                ],
                "productInstallationRootState": product_root_state,
                "productInstallationRootCommand": windows_host_installation_observation.command_document(product_root_command),
                "observedInstallerArtifact": observed_artifact,
            },
            compose_verified_c24_proof(
                evidence_run, REBOOT_STAGE, observed_at, observed_artifact
            )
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
    ) -> WindowsCleanHostReleaseEvidenceStageRecord:
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
    ) -> WindowsCleanHostReleaseEvidenceStageRecord:
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
    ) -> WindowsCleanHostReleaseEvidenceStageRecord:
        """Join update contracts with fresh MSI/SCM/root observations."""

        other_transition_stage = (
            ROLLBACK_STAGE if stage == UPDATE_STAGE else UPDATE_STAGE
        )
        if self.journal.load_stage_record(other_transition_stage) is not None:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence run cannot mix update and rollback "
                "transition scenarios"
            )
        evidence_run = self.require_verified_predecessor(predecessor_stage)
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
        msi_registration = observe_windows_msi_registration(evidence_run)
        service_observations = observe_required_windows_scm_service_registrations(
            evidence_run
        )
        product_root_state, product_root_command = observe_product_root_state(evidence_run)
        if issue is None and transition is not None:
            issue = host_platform_transition_os_issue(
                stage,
                evidence_run,
                transition,
                msi_registration,
                service_observations,
                product_root_state,
            )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        details: dict[str, Any] = {
            "msiRegistrationObservation": windows_host_installation_observation.msi_registration_document(msi_registration),
            "scmServiceRegistrationObservations": [
                windows_host_installation_observation.scm_service_registration_document(observation)
                for observation in service_observations
            ],
            "productInstallationRootState": product_root_state,
            "productInstallationRootCommand": windows_host_installation_observation.command_document(product_root_command),
            "observedInstallerArtifact": observed_artifact,
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
        return self.record_stage_with_c24_proof(
            evidence_run,
            stage,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            compose_verified_c24_proof(evidence_run, stage, observed_at, observed_artifact)
            if issue is None
            else compose_failed_c24_proof(evidence_run, stage, observed_at, issue),
            issue,
        )

    def execute_uninstall_reinstall_preserving_data(
        self,
        removal_receipt_path: Path,
        expected_removal_installation_id: str,
        expected_removal_release_id: str,
    ) -> WindowsCleanHostReleaseEvidenceStageRecord:
        """Prove C54 preservation removal before one explicit MSI reinstall.

        The C48 release slot is immutable package content, while its declared
        data root is mutable Host-owned state.  An MSI exit code or an absent
        ProductCode cannot substitute for the selected C54 completion receipt
        and the two distinct filesystem observations.
        """

        evidence_run = self.require_verified_predecessor(REBOOT_STAGE)
        observed_at = utc_timestamp()
        removal_command = execute_windows_clean_host_command(
            evidence_run.command_contract.msiexec_executable,
            ["/x", evidence_run.msi_product_code, "/qn", "/norestart"],
        )
        removal_registration = observe_windows_msi_registration(evidence_run)
        removal_services = observe_required_windows_scm_service_registrations(evidence_run)
        immutable_root_state, immutable_root_command = observe_windows_path_state(
            evidence_run, evidence_run.product_immutable_release_root
        )
        data_root_state, data_root_command = observe_windows_path_state(
            evidence_run, evidence_run.product_data_root
        )
        removal_receipt, removal_receipt_sha256, removal_receipt_issue = (
            observe_completed_windows_preservation_removal_receipt(
                removal_receipt_path,
                expected_removal_installation_id,
                expected_removal_release_id,
            )
        )
        removal_issue = uninstall_preserving_data_issue(
            removal_command,
            removal_registration,
            removal_services,
            immutable_root_state,
            data_root_state,
            removal_receipt_issue,
        )
        artifact = observed_installer_artifact(evidence_run, observed_at)
        removal_details: dict[str, Any] = {
            "dataDisposition": "preserve-mutable-data",
            "uninstallCommand": windows_host_installation_observation.command_document(
                removal_command
            ),
            "msiRegistrationObservation": windows_host_installation_observation.msi_registration_document(
                removal_registration
            ),
            "scmServiceRegistrationObservations": [
                windows_host_installation_observation.scm_service_registration_document(
                    observation
                )
                for observation in removal_services
            ],
            "immutableReleaseRoot": path_state_observation_document(
                evidence_run.product_immutable_release_root,
                immutable_root_state,
                immutable_root_command,
            ),
            "mutableDataRoot": path_state_observation_document(
                evidence_run.product_data_root, data_root_state, data_root_command
            ),
        }
        if removal_receipt is not None and removal_receipt_sha256 is not None:
            removal_details["hostProductRemovalReceipt"] = {
                "uri": removal_receipt_path.as_uri(),
                "sha256": removal_receipt_sha256,
                "receipt": removal_receipt,
            }
        if removal_issue is not None:
            return self.record_stage_with_c24_proof(
                evidence_run,
                UNINSTALL_REINSTALL_STAGE,
                "failed",
                observed_at,
                removal_details,
                compose_failed_c24_proof(
                    evidence_run,
                    UNINSTALL_REINSTALL_STAGE,
                    observed_at,
                    removal_issue,
                ),
                removal_issue,
            )

        reinstall_command = execute_windows_clean_host_command(
            evidence_run.command_contract.msiexec_executable,
            ["/i", str(evidence_run.installer_artifact_path), "/qn", "/norestart"],
        )
        reinstall_registration = observe_windows_msi_registration(evidence_run)
        reinstall_services = observe_required_windows_scm_service_registrations(evidence_run)
        reinstall_product_root_state, reinstall_product_root_command = observe_product_root_state(
            evidence_run
        )
        reinstall_immutable_root_state, reinstall_immutable_root_command = (
            observe_windows_path_state(evidence_run, evidence_run.product_immutable_release_root)
        )
        reinstall_data_root_state, reinstall_data_root_command = observe_windows_path_state(
            evidence_run, evidence_run.product_data_root
        )
        reinstall_issue = reinstall_after_preserving_removal_issue(
            evidence_run,
            reinstall_command,
            reinstall_registration,
            reinstall_services,
            reinstall_product_root_state,
            reinstall_immutable_root_state,
            reinstall_data_root_state,
        )
        details = {
            **removal_details,
            "reinstallCommand": windows_host_installation_observation.command_document(
                reinstall_command
            ),
            "postReinstall": {
                "msiRegistrationObservation": windows_host_installation_observation.msi_registration_document(
                    reinstall_registration
                ),
                "scmServiceRegistrationObservations": [
                    windows_host_installation_observation.scm_service_registration_document(
                        observation
                    )
                    for observation in reinstall_services
                ],
                "productInstallationRoot": path_state_observation_document(
                    evidence_run.product_installation_root,
                    reinstall_product_root_state,
                    reinstall_product_root_command,
                ),
                "immutableReleaseRoot": path_state_observation_document(
                    evidence_run.product_immutable_release_root,
                    reinstall_immutable_root_state,
                    reinstall_immutable_root_command,
                ),
                "mutableDataRoot": path_state_observation_document(
                    evidence_run.product_data_root,
                    reinstall_data_root_state,
                    reinstall_data_root_command,
                ),
            },
            "observedInstallerArtifact": artifact,
        }
        return self.record_stage_with_c24_proof(
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
                evidence_run,
                UNINSTALL_REINSTALL_STAGE,
                observed_at,
                reinstall_issue,
            ),
            reinstall_issue,
        )

    def require_verified_predecessor(
        self, predecessor_stage: str
    ) -> WindowsCleanHostReleaseEvidenceRun:
        evidence_run = self.journal.load_evidence_run()
        predecessor = self.journal.load_stage_record(predecessor_stage)
        if predecessor is None or predecessor.status != "verified":
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence requires verified predecessor stage: "
                + predecessor_stage
            )
        assert_bound_installer_artifact_is_unchanged(evidence_run)
        return evidence_run

    def record_stage_with_c24_proof(
        self,
        evidence_run: WindowsCleanHostReleaseEvidenceRun,
        stage: str,
        status: str,
        recorded_at: str,
        details: Mapping[str, Any],
        c24_proof: Mapping[str, Any] | None,
        issue: Mapping[str, str] | None = None,
    ) -> WindowsCleanHostReleaseEvidenceStageRecord:
        if self.journal.load_stage_record(stage) is not None:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host release evidence stage was already recorded: " + stage
            )
        evidence_document: dict[str, Any] = {
            "schemaVersion": "v1",
            "evidenceKind": "windows-clean-host-release-stage",
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
            evidence_run.evidence_directory, stage, evidence_document
        )
        if c24_proof is not None:
            c24_proof = {
                **c24_proof,
                "evidence": {"uri": evidence_path.as_uri(), "sha256": evidence_sha256},
            }
        stage_record = WindowsCleanHostReleaseEvidenceStageRecord(
            stage=stage,
            status=status,
            recorded_at=recorded_at,
            evidence_path=evidence_path,
            evidence_sha256=evidence_sha256,
            c24_proof=c24_proof,
        )
        self.journal.record_new_stage(stage_record, details)
        return stage_record


def create_windows_clean_host_release_evidence_run(
    journal_path: Path,
    evidence_directory: Path,
    installer_artifact_path: Path,
    release_delivery_plans_document: Path,
    release_delivery_plan_id: str,
    run_id: str,
    runner_id: str,
    msi_product_code: str,
    product_installation_root: Path,
    product_immutable_release_root: Path,
    product_data_root: Path,
    command_contract: WindowsCleanHostReleaseEvidenceCommandContract,
) -> WindowsCleanHostReleaseEvidenceRun:
    """Bind one exact C23 MSI byte stream to one new evidence journal."""

    validate_evidence_run_input_paths(
        journal_path,
        evidence_directory,
        installer_artifact_path,
        release_delivery_plans_document,
        product_installation_root,
        product_immutable_release_root,
        product_data_root,
        command_contract,
    )
    if not run_id:
        raise WindowsCleanHostReleaseEvidenceRunError("Windows clean-Host evidence run ID is required")
    if not runner_id:
        raise WindowsCleanHostReleaseEvidenceRunError("Windows clean-Host runner ID is required")
    if not msi_product_code:
        raise WindowsCleanHostReleaseEvidenceRunError("Windows MSI ProductCode is required")
    try:
        release_plan = load_selected_windows_host_msi_release_plan(
            release_delivery_plans_document, release_delivery_plan_id
        )
    except ProductDeliveryReleasePlanError as error:
        raise WindowsCleanHostReleaseEvidenceRunError(str(error)) from error
    if installer_artifact_path.name != release_plan.expected_msi_file_name:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host installer artifact file name must match C23 intended installer artifact"
        )
    evidence_run = evidence_run_from_release_plan(
        release_plan,
        installer_artifact_path,
        evidence_directory,
        run_id,
        runner_id,
        msi_product_code,
        product_installation_root,
        product_immutable_release_root,
        product_data_root,
        command_contract,
        utc_timestamp(),
    )
    WindowsCleanHostReleaseEvidenceJournal.create_new(journal_path, evidence_run)
    return evidence_run


def evidence_run_from_release_plan(
    release_plan: WindowsHostMSIReleasePlan,
    installer_artifact_path: Path,
    evidence_directory: Path,
    run_id: str,
    runner_id: str,
    msi_product_code: str,
    product_installation_root: Path,
    product_immutable_release_root: Path,
    product_data_root: Path,
    command_contract: WindowsCleanHostReleaseEvidenceCommandContract,
    created_at: str,
) -> WindowsCleanHostReleaseEvidenceRun:
    return WindowsCleanHostReleaseEvidenceRun(
        run_id=run_id,
        runner_id=runner_id,
        release_delivery_plan_id=release_plan.release_delivery_plan_id,
        product_version=release_plan.product_version,
        intended_installer_file_name=release_plan.expected_msi_file_name,
        msi_product_code=msi_product_code,
        host_agent_windows_scm_service_name=(
            release_plan.host_agent_windows_scm_service_name
        ),
        host_edge_proxy_windows_scm_service_name=(
            release_plan.host_edge_proxy_windows_scm_service_name
        ),
        host_update_handoff_supervisor_windows_scm_service_name=(
            release_plan.host_update_handoff_supervisor_windows_scm_service_name
        ),
        product_installation_root=product_installation_root,
        product_immutable_release_root=product_immutable_release_root,
        product_data_root=product_data_root,
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
    product_installation_root: Path,
    product_immutable_release_root: Path,
    product_data_root: Path,
    command_contract: WindowsCleanHostReleaseEvidenceCommandContract,
) -> None:
    if not journal_path.is_absolute() or not journal_path.parent.is_dir():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host evidence journal path must be absolute and have an existing parent directory"
        )
    if not evidence_directory.is_absolute() or not evidence_directory.is_dir():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host evidence directory must be an existing absolute directory"
        )
    if not installer_artifact_path.is_absolute() or not installer_artifact_path.is_file():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host installer artifact is missing or not an absolute file"
        )
    if not release_delivery_plans_document.is_absolute() or not release_delivery_plans_document.is_file():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "C23 release delivery plans document is missing or not an absolute file"
        )
    if not product_installation_root.is_absolute():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows product installation root must be an absolute path"
        )
    if not product_immutable_release_root.is_absolute():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows product immutable release root must be an absolute path"
        )
    if not product_data_root.is_absolute():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows product data root must be an absolute path"
        )
    if len(
        {
            str(product_installation_root),
            str(product_immutable_release_root),
            str(product_data_root),
        }
    ) != 3:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows product, immutable release, and mutable data roots must be distinct"
        )
    validate_command_contract(command_contract)


def validate_new_journal_path(journal_path: Path) -> None:
    if not journal_path.is_absolute() or not journal_path.parent.is_dir():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host release evidence journal path must be absolute and have an existing parent directory"
        )
    if journal_path.exists():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host release evidence journal already exists"
        )


def validate_command_contract(
    command_contract: WindowsCleanHostReleaseEvidenceCommandContract,
) -> None:
    for executable_name, executable_path in (
        ("PowerShell", command_contract.powershell_executable),
        ("msiexec", command_contract.msiexec_executable),
        ("reg.exe", command_contract.registry_executable),
        ("sc.exe", command_contract.sc_executable),
    ):
        if not executable_path.is_absolute() or not executable_path.is_file():
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host "
                + executable_name
                + " executable is missing or not an absolute file"
            )


def command_contract_document(
    command_contract: WindowsCleanHostReleaseEvidenceCommandContract,
) -> Mapping[str, str]:
    return {
        "powershellExecutable": str(command_contract.powershell_executable),
        "msiexecExecutable": str(command_contract.msiexec_executable),
        "registryExecutable": str(command_contract.registry_executable),
        "scExecutable": str(command_contract.sc_executable),
    }


def command_contract_from_journal_document(
    document: Any,
) -> WindowsCleanHostReleaseEvidenceCommandContract:
    if not isinstance(document, dict):
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host release evidence command contract must be an object"
        )
    return WindowsCleanHostReleaseEvidenceCommandContract(
        powershell_executable=Path(
            required_non_empty_string(document.get("powershellExecutable"), "journal PowerShell executable")
        ),
        msiexec_executable=Path(
            required_non_empty_string(document.get("msiexecExecutable"), "journal msiexec executable")
        ),
        registry_executable=Path(
            required_non_empty_string(document.get("registryExecutable"), "journal registry executable")
        ),
        sc_executable=Path(
            required_non_empty_string(document.get("scExecutable"), "journal SCM executable")
        ),
    )


def assert_bound_installer_artifact_is_unchanged(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
) -> None:
    if not evidence_run.installer_artifact_path.is_absolute() or not evidence_run.installer_artifact_path.is_file():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "bound Windows clean-Host installer artifact is missing or not a file"
        )
    if sha256_file(evidence_run.installer_artifact_path) != evidence_run.bound_installer_artifact_sha256:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "bound Windows clean-Host installer artifact SHA-256 changed after evidence run creation"
        )


def observed_installer_artifact(
    evidence_run: WindowsCleanHostReleaseEvidenceRun, observed_at: str
) -> Mapping[str, str]:
    assert_bound_installer_artifact_is_unchanged(evidence_run)
    return {
        "kind": "msi",
        "fileName": evidence_run.intended_installer_file_name,
        "productVersion": evidence_run.product_version,
        "sha256": evidence_run.bound_installer_artifact_sha256,
        "observedAt": observed_at,
    }


def execute_windows_clean_host_command(
    executable: Path, arguments: Sequence[str]
) -> windows_host_installation_observation.WindowsHostInstallationCommandObservation:
    try:
        return windows_host_installation_observation.execute_windows_host_installation_command(
            executable, arguments
        )
    except windows_host_installation_observation.WindowsHostInstallationObservationError as error:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host command execution failed: " + str(error)
        ) from error


def observe_windows_msi_artifact_release_identity(
    powershell_executable: Path, installer_artifact_path: Path
) -> windows_host_installation_observation.WindowsMSIArtifactIdentityObservation:
    return windows_host_installation_observation.observe_windows_msi_artifact_identity(
        powershell_executable,
        installer_artifact_path,
        execute_command=execute_windows_clean_host_command,
    )


def observe_windows_msi_registration(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
) -> windows_host_installation_observation.WindowsMSIRegistrationObservation:
    return windows_host_installation_observation.observe_windows_msi_registration(
        evidence_run.command_contract.registry_executable,
        evidence_run.msi_product_code,
        execute_command=execute_windows_clean_host_command,
    )


def observe_required_windows_scm_service_registrations(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
) -> list[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation]:
    return [
        windows_host_installation_observation.observe_windows_scm_service_registration(
            evidence_run.command_contract.sc_executable,
            role,
            service_name,
            execute_command=execute_windows_clean_host_command,
        )
        for role, service_name in (
            ("host-agent", evidence_run.host_agent_windows_scm_service_name),
            ("host-edge-proxy", evidence_run.host_edge_proxy_windows_scm_service_name),
            (
                "host-update-handoff-supervisor",
                evidence_run.host_update_handoff_supervisor_windows_scm_service_name,
            ),
        )
    ]


def observe_product_root_state(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
) -> tuple[str, windows_host_installation_observation.WindowsHostInstallationCommandObservation]:
    return observe_windows_path_state(evidence_run, evidence_run.product_installation_root)


def observe_windows_path_state(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    path: Path,
) -> tuple[str, windows_host_installation_observation.WindowsHostInstallationCommandObservation]:
    """Observe one caller-declared C48 path without deriving a root from it."""

    command = execute_windows_clean_host_command(
        evidence_run.command_contract.powershell_executable,
        [
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "if(Test-Path -LiteralPath $args[0]){[Console]::Out.Write('present')}else{[Console]::Out.Write('absent')}",
            str(path),
        ],
    )
    state = command.stdout.strip()
    if command.returncode != 0 or state not in {"present", "absent"}:
        return "unavailable", command
    return state, command


def path_state_observation_document(
    path: Path,
    state: str,
    command: windows_host_installation_observation.WindowsHostInstallationCommandObservation,
) -> Mapping[str, Any]:
    return {
        "path": str(path),
        "state": state,
        "command": windows_host_installation_observation.command_document(command),
    }


def observe_windows_host_boot_session(
    powershell_executable: Path,
) -> windows_host_installation_observation.WindowsHostBootSessionObservation:
    try:
        return windows_host_installation_observation.observe_windows_host_boot_session(
            powershell_executable, execute_command=execute_windows_clean_host_command
        )
    except windows_host_installation_observation.WindowsHostInstallationObservationError as error:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host boot session identifier is unavailable: " + str(error)
        ) from error


def windows_msi_artifact_integrity_issue(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    identity: windows_host_installation_observation.WindowsMSIArtifactIdentityObservation,
) -> Mapping[str, str] | None:
    if identity.state != "available":
        return {
            "code": "windows-msi-metadata-or-signature-unavailable",
            "message": "Windows could not provide readable MSI metadata and Authenticode status for the selected installer.",
        }
    if identity.product_version != evidence_run.product_version:
        return {
            "code": "windows-msi-product-version-mismatch",
            "message": "The observed MSI ProductVersion does not match C23.",
        }
    if identity.signature_state != "Valid":
        return {
            "code": "windows-msi-signature-not-valid",
            "message": "The selected MSI did not report Authenticode status Valid.",
        }
    return None


def clean_host_preflight_issue(
    msi_registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
    service_observations: Sequence[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation],
    product_root_state: str,
) -> Mapping[str, str] | None:
    if msi_registration.state == "installed":
        return {
            "code": "windows-clean-host-msi-already-installed",
            "message": "The C23 MSI ProductCode is already registered, so this Host is not clean.",
        }
    if msi_registration.state != "absent":
        return {
            "code": "windows-clean-host-msi-registration-observation-unavailable",
            "message": "The C23 MSI ProductCode absence could not be observed explicitly.",
        }
    for observation in service_observations:
        if observation.state == "registered":
            return {
                "code": "windows-clean-host-scm-service-already-registered",
                "message": "A C23-required SCM service is already registered, so this Host is not clean.",
            }
        if observation.state != "absent":
            return {
                "code": "windows-clean-host-scm-service-observation-unavailable",
                "message": "A C23-required SCM service absence could not be observed explicitly.",
            }
    if product_root_state == "present":
        return {
            "code": "windows-clean-host-product-root-already-present",
            "message": "The declared Windows product installation root is present, so this Host is not clean.",
        }
    if product_root_state != "absent":
        return {
            "code": "windows-clean-host-product-root-observation-unavailable",
            "message": "The declared Windows product installation root absence could not be observed explicitly.",
        }
    return None


def clean_install_issue(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    installer_command: windows_host_installation_observation.WindowsHostInstallationCommandObservation,
    msi_registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
) -> Mapping[str, str] | None:
    if installer_command.returncode != 0:
        return {
            "code": "windows-clean-install-command-failed",
            "message": "msiexec returned a non-zero result for the selected C23 MSI.",
        }
    return installed_msi_registration_issue(evidence_run, msi_registration)


def installed_msi_registration_issue(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    msi_registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
) -> Mapping[str, str] | None:
    if msi_registration.state != "installed":
        return {
            "code": "windows-installed-msi-registration-not-observed",
            "message": "The C23 MSI ProductCode was not observed as installed after the installer effect.",
        }
    if msi_registration.product_version != evidence_run.product_version:
        return {
            "code": "windows-installed-msi-version-mismatch",
            "message": "The observed installed MSI DisplayVersion does not match C23.",
        }
    return None


def installed_receipt_or_service_registration_issue(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    msi_registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
    service_observations: Sequence[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation],
    product_root_state: str,
) -> Mapping[str, str] | None:
    receipt_issue = installed_msi_registration_issue(evidence_run, msi_registration)
    if receipt_issue is not None:
        return receipt_issue
    for observation in service_observations:
        if observation.state != "registered":
            return {
                "code": "windows-scm-service-registration-not-observed",
                "message": "A C23-required SCM service was not observed as registered.",
            }
    if product_root_state != "present":
        return {
            "code": "windows-product-installation-root-not-observed",
            "message": "The declared Windows product installation root was not observed as present.",
        }
    return None


def reboot_persistence_issue(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    checkpoint_identifier: str,
    current_boot_session: windows_host_installation_observation.WindowsHostBootSessionObservation,
    msi_registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
    service_observations: Sequence[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation],
    product_root_state: str,
) -> Mapping[str, str] | None:
    if current_boot_session.boot_session_identifier == checkpoint_identifier:
        return {
            "code": "windows-reboot-not-observed",
            "message": "The Windows boot-session identifier did not change after the reboot checkpoint.",
        }
    return installed_receipt_or_service_registration_issue(
        evidence_run, msi_registration, service_observations, product_root_state
    )


def observe_host_platform_transition(
    stage: str,
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    release_delivery_plans_document: Path,
    host_update_journal_path: Path,
    host_platform_effect_receipt_path: Path,
    host_installation_manifest_path: Path,
    host_installation_footprint_path: Path,
) -> tuple[
    host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence | None,
    Mapping[str, str] | None,
]:
    """Read C29/C28/C55/C48/C49 facts without promoting them to C24 alone."""

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
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows Host Platform transition stage is unsupported: " + stage
            )
    except host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidenceError as error:
        return None, {
            "code": "windows-host-platform-" + stage + "-transition-invalid",
            "message": "C29/C28/C55/C48/C49 transition evidence is invalid: " + str(error),
        }
    if (
        transition.release_delivery_plan_id != evidence_run.release_delivery_plan_id
        or transition.platform != "windows"
        or transition.provider_kind != "windows-hyperv-scm"
        or transition.target_product_version != evidence_run.product_version
    ):
        return None, {
            "code": "windows-host-platform-" + stage + "-transition-identity-mismatch",
            "message": "C29/C28/C55/C48/C49 transition evidence does not match this Windows C24 evidence run.",
        }
    return transition, None


def transition_release_plan_issue(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    release_delivery_plans_document: Path,
) -> Mapping[str, str] | None:
    """Reject an explicit C23 source that differs from the run it would prove."""

    try:
        release_plan = load_selected_windows_host_msi_release_plan(
            release_delivery_plans_document, evidence_run.release_delivery_plan_id
        )
    except ProductDeliveryReleasePlanError as error:
        return {
            "code": "windows-host-platform-transition-release-plan-unavailable",
            "message": "The explicit C23 document cannot be selected for this C24 run: " + str(error),
        }
    if (
        release_plan.product_version != evidence_run.product_version
        or release_plan.expected_msi_file_name != evidence_run.intended_installer_file_name
        or release_plan.host_agent_windows_scm_service_name
        != evidence_run.host_agent_windows_scm_service_name
        or release_plan.host_edge_proxy_windows_scm_service_name
        != evidence_run.host_edge_proxy_windows_scm_service_name
        or release_plan.host_update_handoff_supervisor_windows_scm_service_name
        != evidence_run.host_update_handoff_supervisor_windows_scm_service_name
    ):
        return {
            "code": "windows-host-platform-transition-release-plan-mismatch",
            "message": "The explicit C23 document does not preserve this run's MSI and SCM identities.",
        }
    return None


def host_platform_transition_os_issue(
    stage: str,
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    transition: host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence,
    msi_registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
    service_observations: Sequence[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation],
    product_root_state: str,
) -> Mapping[str, str] | None:
    """Require fresh Windows observations to agree with the C48/C49 result."""

    if msi_registration.state != "installed":
        return {
            "code": "windows-host-platform-" + stage + "-msi-not-installed",
            "message": "reg.exe did not explicitly report the Host Platform MSI ProductCode as installed after the transition.",
        }
    if msi_registration.product_version != transition.observed_product_version:
        return {
            "code": "windows-host-platform-" + stage + "-msi-version-mismatch",
            "message": "The fresh MSI DisplayVersion does not match the C48/C49 transition observation.",
        }
    if any(observation.state != "registered" for observation in service_observations):
        return {
            "code": "windows-host-platform-" + stage + "-service-registration-not-observed",
            "message": "A required SCM service was not registered after the Host Platform transition.",
        }
    if product_root_state != "present":
        return {
            "code": "windows-host-platform-" + stage + "-root-not-observed",
            "message": "The declared Windows product root was not present after the Host Platform transition.",
        }
    if stage == UPDATE_STAGE and msi_registration.product_version != evidence_run.product_version:
        return {
            "code": "windows-host-platform-update-target-version-mismatch",
            "message": "The successful update did not leave the C23 target product version installed.",
        }
    return None


def observe_completed_windows_preservation_removal_receipt(
    receipt_path: Path,
    expected_installation_id: str,
    expected_release_id: str,
) -> tuple[Mapping[str, Any] | None, str | None, Mapping[str, str] | None]:
    """Read one completed C54 receipt without treating a missing file as removal."""

    if not expected_installation_id or not expected_release_id:
        return None, None, {
            "code": "windows-removal-receipt-identity-not-declared",
            "message": "The C54 installation and release identities must be explicit.",
        }
    if not receipt_path.is_absolute() or receipt_path.is_symlink() or not receipt_path.is_file():
        return None, None, {
            "code": "windows-removal-receipt-unavailable",
            "message": "The C54 removal receipt must be one absolute regular non-symlink file.",
        }
    try:
        payload = receipt_path.read_bytes()
        receipt = json.loads(payload)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return None, None, {
            "code": "windows-removal-receipt-unreadable",
            "message": "The C54 removal receipt could not be decoded: " + str(error),
        }
    if not isinstance(receipt, dict):
        return None, None, {
            "code": "windows-removal-receipt-invalid",
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
            "code": "windows-removal-receipt-does-not-prove-preserving-completion",
            "message": "The C54 receipt does not match the declared completed Windows preservation removal.",
        }
    for field in ("id", "requestId", "observedAt"):
        if not isinstance(receipt.get(field), str) or not receipt[field]:
            return None, None, {
                "code": "windows-removal-receipt-invalid",
                "message": "The C54 receipt is missing required field " + field + ".",
            }
    retained = receipt.get("retainedMutableStoreIds")
    if retained is not None and (
        not isinstance(retained, list)
        or any(not isinstance(item, str) or not item for item in retained)
        or len(set(retained)) != len(retained)
    ):
        return None, None, {
            "code": "windows-removal-receipt-invalid",
            "message": "The C54 receipt retained mutable store IDs are invalid.",
        }
    return receipt, hashlib.sha256(payload).hexdigest(), None


def uninstall_preserving_data_issue(
    removal_command: windows_host_installation_observation.WindowsHostInstallationCommandObservation,
    registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
    services: Sequence[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation],
    immutable_release_root_state: str,
    data_root_state: str,
    removal_receipt_issue: Mapping[str, str] | None,
) -> Mapping[str, str] | None:
    if removal_command.returncode != 0:
        return {
            "code": "windows-uninstall-command-failed",
            "message": "msiexec returned a non-zero result for the explicit MSI removal.",
        }
    if removal_receipt_issue is not None:
        return removal_receipt_issue
    if registration.state != "absent":
        return {
            "code": "windows-uninstall-msi-registration-remains",
            "message": "Windows did not explicitly report the removed MSI ProductCode as absent.",
        }
    if any(service.state != "absent" for service in services):
        return {
            "code": "windows-uninstall-scm-service-registration-remains",
            "message": "A C23-required SCM service remained registered after removal.",
        }
    if immutable_release_root_state != "absent" or data_root_state != "present":
        return {
            "code": "windows-uninstall-preservation-state-not-observed",
            "message": "Removal did not explicitly leave immutable release content absent and mutable data present.",
        }
    return None


def reinstall_after_preserving_removal_issue(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    reinstall_command: windows_host_installation_observation.WindowsHostInstallationCommandObservation,
    registration: windows_host_installation_observation.WindowsMSIRegistrationObservation,
    services: Sequence[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation],
    product_installation_root_state: str,
    immutable_release_root_state: str,
    data_root_state: str,
) -> Mapping[str, str] | None:
    if reinstall_command.returncode != 0:
        return {
            "code": "windows-reinstall-command-failed",
            "message": "msiexec returned a non-zero result for explicit MSI reinstallation.",
        }
    installed_issue = installed_receipt_or_service_registration_issue(
        evidence_run, registration, services, product_installation_root_state
    )
    if installed_issue is not None:
        return installed_issue
    if immutable_release_root_state != "present" or data_root_state != "present":
        return {
            "code": "windows-reinstall-product-root-not-observed",
            "message": "The reinstalled immutable release root and retained mutable data root were not both observed as present.",
        }
    return None


def compose_verified_c24_proof(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    stage: str,
    recorded_at: str,
    observed_artifact: Mapping[str, str],
    optional_stage_observation: Any | None = None,
) -> Mapping[str, Any]:
    proof: dict[str, Any] = {
        "planId": evidence_run.release_delivery_plan_id,
        "platform": "windows",
        "providerKind": "windows-hyperv-scm",
        "stage": stage,
        "status": "verified",
        "recordedAt": recorded_at,
        "runner": {"kind": "windows-clean-host", "id": evidence_run.runner_id},
        "observedInstallerArtifact": dict(observed_artifact),
    }
    if stage == SERVICE_REGISTRATION_STAGE:
        proof["observedHostServiceRegistrations"] = optional_stage_observation
    return proof


def compose_failed_c24_proof(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
    stage: str,
    recorded_at: str,
    issue: Mapping[str, str],
) -> Mapping[str, Any]:
    return {
        "planId": evidence_run.release_delivery_plan_id,
        "platform": "windows",
        "providerKind": "windows-hyperv-scm",
        "stage": stage,
        "status": "failed",
        "recordedAt": recorded_at,
        "runner": {"kind": "windows-clean-host", "id": evidence_run.runner_id},
        "issue": dict(issue),
    }


def observed_host_service_registrations(
    observations: Sequence[windows_host_installation_observation.WindowsSCMServiceRegistrationObservation],
    observed_at: str,
) -> list[Mapping[str, str]]:
    registrations: list[Mapping[str, str]] = []
    for observation in observations:
        if observation.state != "registered":
            raise WindowsCleanHostReleaseEvidenceRunError(
                "cannot compose an observed Windows SCM service registration from "
                + observation.state
            )
        registrations.append(
            {
                "role": observation.role,
                "manager": "windows-scm",
                "name": observation.service_name,
                "registrationState": "registered",
                "observedAt": observed_at,
            }
        )
    return registrations


def release_identity_document(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
) -> Mapping[str, str]:
    return {
        "productVersion": evidence_run.product_version,
        "intendedInstallerFileName": evidence_run.intended_installer_file_name,
        "msiProductCode": evidence_run.msi_product_code,
        "hostAgentWindowsSCMServiceName": evidence_run.host_agent_windows_scm_service_name,
        "hostEdgeProxyWindowsSCMServiceName": evidence_run.host_edge_proxy_windows_scm_service_name,
        "hostUpdateHandoffSupervisorWindowsSCMServiceName": evidence_run.host_update_handoff_supervisor_windows_scm_service_name,
        "productInstallationRoot": str(evidence_run.product_installation_root),
        "productImmutableReleaseRoot": str(evidence_run.product_immutable_release_root),
        "productDataRoot": str(evidence_run.product_data_root),
        "boundInstallerArtifactSHA256": evidence_run.bound_installer_artifact_sha256,
    }


def boot_session_identifier_from_checkpoint(details: Mapping[str, Any]) -> str:
    observation = details.get("bootSessionObservation")
    if not isinstance(observation, dict):
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows reboot checkpoint does not contain a boot-session observation"
        )
    return required_non_empty_string(
        observation.get("bootSessionIdentifier"), "Windows reboot checkpoint boot-session identifier"
    )


def write_new_evidence_document(
    evidence_directory: Path, stage: str, evidence_document: Mapping[str, Any]
) -> tuple[Path, str]:
    validate_release_evidence_stage(stage)
    if not evidence_directory.is_absolute() or not evidence_directory.is_dir():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host evidence directory is missing or not an absolute directory"
        )
    evidence_path = evidence_directory / (stage + ".json")
    if evidence_path.exists():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host evidence document already exists for stage: " + stage
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
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host evidence document write failed: " + str(error)
        ) from error
    return evidence_path, sha256_file(evidence_path)


def write_new_c24_proof_fragment(
    output_proof_fragment_path: Path,
    stage_record: WindowsCleanHostReleaseEvidenceStageRecord,
) -> tuple[Path, str]:
    """Write one immutable C24 fragment from runner-owned journal state."""

    if stage_record.c24_proof is None:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host release evidence stage has no C24 proof: "
            + stage_record.stage
        )
    if not output_proof_fragment_path.is_absolute():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows C24 proof fragment output path must be absolute"
        )
    if not output_proof_fragment_path.parent.is_dir():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows C24 proof fragment output parent directory is missing: "
            + str(output_proof_fragment_path.parent)
        )
    if output_proof_fragment_path.exists() or output_proof_fragment_path.is_symlink():
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows C24 proof fragment output already exists: "
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
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows C24 proof fragment output already exists: "
            + str(output_proof_fragment_path)
        ) from error
    except OSError as error:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows C24 proof fragment write failed: " + str(error)
        ) from error
    return output_proof_fragment_path, sha256_file(output_proof_fragment_path)


def stage_record_document(
    stage_record: WindowsCleanHostReleaseEvidenceStageRecord,
) -> Mapping[str, Any]:
    return {
        "stage": stage_record.stage,
        "status": stage_record.status,
        "recordedAt": stage_record.recorded_at,
        "evidencePath": str(stage_record.evidence_path),
        "evidenceSHA256": stage_record.evidence_sha256,
        "c24Proof": stage_record.c24_proof,
    }


def evidence_run_document(
    evidence_run: WindowsCleanHostReleaseEvidenceRun,
) -> Mapping[str, Any]:
    """Format the owned run identity for the command boundary only."""

    return {
        "runId": evidence_run.run_id,
        "runnerId": evidence_run.runner_id,
        "releaseDeliveryPlanId": evidence_run.release_delivery_plan_id,
        "releaseIdentity": release_identity_document(evidence_run),
        "installerArtifactPath": str(evidence_run.installer_artifact_path),
        "evidenceDirectory": str(evidence_run.evidence_directory),
        "commandContract": command_contract_document(evidence_run.command_contract),
        "createdAt": evidence_run.created_at,
    }


def validate_release_evidence_stage(stage: str) -> None:
    if stage not in RELEASE_EVIDENCE_STAGES:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "unknown Windows clean-Host release evidence stage: " + stage
        )


def required_non_empty_string(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise WindowsCleanHostReleaseEvidenceRunError(name + " must be a non-empty string")
    return value


def required_sha256(value: Any, name: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise WindowsCleanHostReleaseEvidenceRunError(name + " must be a lowercase SHA-256")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host file digest read failed: " + str(error)
        ) from error
    return digest.hexdigest()


def canonical_json(document: Any) -> str:
    return json.dumps(document, sort_keys=True, separators=(",", ":"))


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def require_windows_host_platform() -> None:
    if platform.system() != "Windows":
        raise WindowsCleanHostReleaseEvidenceRunError(
            "Windows clean-Host release evidence CLI requires a Windows Host"
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
    create.add_argument("--msi-product-code", required=True)
    create.add_argument("--product-installation-root", required=True, type=Path)
    create.add_argument("--product-immutable-release-root", required=True, type=Path)
    create.add_argument("--product-data-root", required=True, type=Path)
    for executable in ("powershell", "msiexec", "registry", "sc"):
        create.add_argument("--" + executable + "-executable", required=True, type=Path)
    for operation in (
        "record-artifact-integrity",
        "record-clean-host-preflight",
        "record-service-registration",
        "record-reboot-checkpoint",
        "record-reboot",
    ):
        subparser = subparsers.add_parser(operation)
        subparser.add_argument("--journal", required=True, type=Path)
    write_fragment = subparsers.add_parser("write-stage-proof-fragment")
    write_fragment.add_argument("--journal", required=True, type=Path)
    write_fragment.add_argument("--stage", required=True, choices=C24_PROOF_STAGES)
    write_fragment.add_argument("--output-proof-fragment", required=True, type=Path)
    clean_install = subparsers.add_parser("execute-clean-install")
    clean_install.add_argument("--journal", required=True, type=Path)
    clean_install.add_argument(
        "--authorize-clean-install",
        action="store_true",
        help="explicitly authorize the elevated MSI installation effect",
    )
    for operation in ("record-host-platform-update", "record-host-platform-rollback"):
        subparser = subparsers.add_parser(operation)
        subparser.add_argument("--journal", required=True, type=Path)
        subparser.add_argument("--release-delivery-plans-document", required=True, type=Path)
        subparser.add_argument("--host-update-journal", required=True, type=Path)
        subparser.add_argument("--host-platform-effect-receipt", required=True, type=Path)
        subparser.add_argument("--host-installation-manifest", required=True, type=Path)
        subparser.add_argument("--host-installation-footprint", required=True, type=Path)
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
        help="explicitly authorize the elevated MSI removal and reinstall effects",
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        require_windows_host_platform()
        if parsed.operation == "create-run":
            evidence_run = create_windows_clean_host_release_evidence_run(
                journal_path=parsed.journal,
                evidence_directory=parsed.evidence_directory,
                installer_artifact_path=parsed.installer_artifact,
                release_delivery_plans_document=parsed.release_delivery_plans_document,
                release_delivery_plan_id=parsed.release_delivery_plan_id,
                run_id=parsed.run_id,
                runner_id=parsed.runner_id,
                msi_product_code=parsed.msi_product_code,
                product_installation_root=parsed.product_installation_root,
                product_immutable_release_root=parsed.product_immutable_release_root,
                product_data_root=parsed.product_data_root,
                command_contract=WindowsCleanHostReleaseEvidenceCommandContract(
                    powershell_executable=parsed.powershell_executable,
                    msiexec_executable=parsed.msiexec_executable,
                    registry_executable=parsed.registry_executable,
                    sc_executable=parsed.sc_executable,
                ),
            )
            print(canonical_json({"evidenceRun": evidence_run_document(evidence_run)}))
            return 0
        if parsed.operation == "execute-clean-install" and not parsed.authorize_clean_install:
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host installation requires --authorize-clean-install"
            )
        if (
            parsed.operation == "execute-uninstall-reinstall-preserving-data"
            and not parsed.authorize_uninstall_reinstall
        ):
            raise WindowsCleanHostReleaseEvidenceRunError(
                "Windows clean-Host preservation removal and reinstall require --authorize-uninstall-reinstall"
            )
        runner = WindowsCleanHostReleaseEvidenceRunner(
            WindowsCleanHostReleaseEvidenceJournal(parsed.journal)
        )
        if parsed.operation == "write-stage-proof-fragment":
            stage_record = runner.journal.load_stage_record(parsed.stage)
            if stage_record is None:
                raise WindowsCleanHostReleaseEvidenceRunError(
                    "Windows clean-Host release evidence stage has no C24 proof: "
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
        stage_method = {
            "record-artifact-integrity": runner.record_artifact_integrity,
            "record-clean-host-preflight": runner.record_clean_host_preflight,
            "execute-clean-install": runner.execute_clean_install,
            "record-service-registration": runner.record_service_registration,
            "record-reboot-checkpoint": runner.record_reboot_checkpoint,
            "record-reboot": runner.record_reboot,
        }[parsed.operation]
        print(canonical_json(stage_record_document(stage_method())))
        return 0
    except WindowsCleanHostReleaseEvidenceRunError as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
