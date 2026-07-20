#!/usr/bin/env python3
"""Collect explicit macOS unsigned-development-installation evidence.

This development-process tool proves only a controlled local installation of
an unsigned PKG whose installed macOS Virtual Machine Supervisor carries an
ad-hoc signature with the virtualization entitlement.  It deliberately does
not create C24 release evidence, change release-delivery proofs, claim Apple
Developer ID distribution, or infer Guest Runtime readiness from package or
launchd facts.

The tool owns one ``MacOSDevelopmentInstallationEvidenceRun`` and its SQLite
journal.  macOS Installer, launchd, and codesign remain external state owners;
their exact command results are retained as evidence.
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
import sys
import tempfile
from typing import Any, Mapping, Sequence

from tooling import macos_host_installation_observation
from tooling.product_delivery_release_plan import (
    MacOSHostPackageReleasePlan,
    ProductDeliveryReleasePlanError,
    load_selected_macos_host_package_release_plan,
)


class MacOSDevelopmentInstallationEvidenceRunError(RuntimeError):
    """A development-installation evidence fact is unavailable or unsafe."""


ARTIFACT_IDENTITY_STAGE = "artifact-identity"
CLEAN_HOST_PREFLIGHT_STAGE = "clean-host-preflight"
INSTALLATION_STAGE = "installation"
SERVICE_REGISTRATION_STAGE = "service-registration"
SUPERVISOR_SIGNATURE_STAGE = "supervisor-signature"
REBOOT_CHECKPOINT_STAGE = "reboot-checkpoint"
REBOOT_STAGE = "reboot"

DEVELOPMENT_INSTALLATION_STAGES = {
    ARTIFACT_IDENTITY_STAGE,
    CLEAN_HOST_PREFLIGHT_STAGE,
    INSTALLATION_STAGE,
    SERVICE_REGISTRATION_STAGE,
    SUPERVISOR_SIGNATURE_STAGE,
    REBOOT_CHECKPOINT_STAGE,
    REBOOT_STAGE,
}


@dataclass(frozen=True)
class MacOSDevelopmentInstallationCommandContract:
    """Explicit macOS executables through which this development run observes facts."""

    pkgutil_executable: Path
    installer_executable: Path
    launchctl_executable: Path
    codesign_executable: Path
    sysctl_executable: Path


@dataclass(frozen=True)
class MacOSDevelopmentInstallationEvidenceRun:
    """Development-process-owned durable identity for one local installation run."""

    run_id: str
    runner_id: str
    release_delivery_plan_id: str
    product_version: str
    intended_installer_file_name: str
    macos_installer_package_identifier: str
    host_agent_launchd_service_label: str
    host_edge_proxy_launchd_service_label: str
    host_update_handoff_supervisor_launchd_service_label: str
    installed_virtual_machine_supervisor_path: Path
    installer_artifact_path: Path
    bound_installer_artifact_sha256: str
    evidence_directory: Path
    command_contract: MacOSDevelopmentInstallationCommandContract
    created_at: str


@dataclass(frozen=True)
class MacOSDevelopmentInstallationEvidenceStageRecord:
    """One immutable development evidence result recorded in the journal."""

    stage: str
    status: str
    recorded_at: str
    evidence_path: Path
    evidence_sha256: str


class MacOSDevelopmentInstallationEvidenceJournal:
    """SQLite owner for one development installation evidence run and its stages.

    This journal is intentionally not the C24 release-evidence journal and not
    Host Agent state.  A local unsigned installation is useful functional
    evidence but has a different purpose, trust level, and retention rule.
    """

    def __init__(self, journal_path: Path):
        self.journal_path = journal_path

    @classmethod
    def create_new(
        cls,
        journal_path: Path,
        evidence_run: MacOSDevelopmentInstallationEvidenceRun,
    ) -> "MacOSDevelopmentInstallationEvidenceJournal":
        validate_new_journal_path(journal_path)
        journal = cls(journal_path)
        try:
            with sqlite3.connect(journal_path) as connection:
                connection.executescript(
                    """
                    CREATE TABLE development_installation_run (
                        run_id TEXT PRIMARY KEY,
                        runner_id TEXT NOT NULL,
                        release_delivery_plan_id TEXT NOT NULL,
                        product_version TEXT NOT NULL,
                        intended_installer_file_name TEXT NOT NULL,
                        macos_installer_package_identifier TEXT NOT NULL,
                        host_agent_launchd_service_label TEXT NOT NULL,
                        host_edge_proxy_launchd_service_label TEXT NOT NULL,
                        host_update_handoff_supervisor_launchd_service_label TEXT NOT NULL,
                        installed_virtual_machine_supervisor_path TEXT NOT NULL,
                        installer_artifact_path TEXT NOT NULL,
                        bound_installer_artifact_sha256 TEXT NOT NULL,
                        evidence_directory TEXT NOT NULL,
                        command_contract_json TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    );
                    CREATE TABLE development_installation_stage (
                        stage TEXT PRIMARY KEY,
                        status TEXT NOT NULL,
                        recorded_at TEXT NOT NULL,
                        evidence_path TEXT NOT NULL,
                        evidence_sha256 TEXT NOT NULL,
                        details_json TEXT NOT NULL
                    );
                    """
                )
                connection.execute(
                    """
                    INSERT INTO development_installation_run (
                        run_id, runner_id, release_delivery_plan_id,
                        product_version, intended_installer_file_name,
                        macos_installer_package_identifier,
                        host_agent_launchd_service_label,
                        host_edge_proxy_launchd_service_label,
                        host_update_handoff_supervisor_launchd_service_label,
                        installed_virtual_machine_supervisor_path,
                        installer_artifact_path,
                        bound_installer_artifact_sha256, evidence_directory,
                        command_contract_json, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        evidence_run.host_update_handoff_supervisor_launchd_service_label,
                        str(evidence_run.installed_virtual_machine_supervisor_path),
                        str(evidence_run.installer_artifact_path),
                        evidence_run.bound_installer_artifact_sha256,
                        str(evidence_run.evidence_directory),
                        canonical_json(
                            command_contract_document(evidence_run.command_contract)
                        ),
                        evidence_run.created_at,
                    ),
                )
        except sqlite3.Error as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence journal creation failed: "
                + str(error)
            ) from error
        return journal

    def load_evidence_run(self) -> MacOSDevelopmentInstallationEvidenceRun:
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT * FROM development_installation_run"
            ).fetchone()
        except sqlite3.Error as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence journal read failed: "
                + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence journal has no evidence run"
            )
        try:
            command_contract_document_value = json.loads(
                row["command_contract_json"]
            )
        except (TypeError, json.JSONDecodeError) as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence journal command contract is unreadable"
            ) from error
        command_contract = command_contract_from_journal_document(
            command_contract_document_value
        )
        validate_command_contract(command_contract)
        return MacOSDevelopmentInstallationEvidenceRun(
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
            host_update_handoff_supervisor_launchd_service_label=(
                required_non_empty_string(
                    row["host_update_handoff_supervisor_launchd_service_label"],
                    "journal Host Update Handoff Supervisor launchd service label",
                )
            ),
            installed_virtual_machine_supervisor_path=Path(
                required_non_empty_string(
                    row["installed_virtual_machine_supervisor_path"],
                    "journal installed macOS virtual machine supervisor path",
                )
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
    ) -> MacOSDevelopmentInstallationEvidenceStageRecord | None:
        validate_development_installation_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT * FROM development_installation_stage WHERE stage = ?",
                (stage,),
            ).fetchone()
        except sqlite3.Error as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence stage read failed: "
                + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            return None
        return MacOSDevelopmentInstallationEvidenceStageRecord(
            stage=required_non_empty_string(row["stage"], "journal stage"),
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
        )

    def load_stage_details(self, stage: str) -> Mapping[str, Any]:
        validate_development_installation_stage(stage)
        connection = self.open_existing_connection()
        try:
            row = connection.execute(
                "SELECT details_json FROM development_installation_stage WHERE stage = ?",
                (stage,),
            ).fetchone()
        except sqlite3.Error as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence stage details read failed: "
                + str(error)
            ) from error
        finally:
            connection.close()
        if row is None:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence stage is not recorded: " + stage
            )
        try:
            details = json.loads(row["details_json"])
        except (TypeError, json.JSONDecodeError) as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence stage details are unreadable"
            ) from error
        if not isinstance(details, dict):
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence stage details must be an object"
            )
        return details

    def record_new_stage(
        self,
        stage_record: MacOSDevelopmentInstallationEvidenceStageRecord,
        details: Mapping[str, Any],
    ) -> None:
        validate_development_installation_stage(stage_record.stage)
        if stage_record.status not in {"verified", "failed"}:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence stage status must be verified or failed"
            )
        connection = self.open_existing_connection()
        try:
            existing = connection.execute(
                "SELECT stage FROM development_installation_stage WHERE stage = ?",
                (stage_record.stage,),
            ).fetchone()
            if existing is not None:
                raise MacOSDevelopmentInstallationEvidenceRunError(
                    "macOS development installation evidence stage was already recorded: "
                    + stage_record.stage
                )
            connection.execute(
                """
                INSERT INTO development_installation_stage (
                    stage, status, recorded_at, evidence_path, evidence_sha256,
                    details_json
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    stage_record.stage,
                    stage_record.status,
                    stage_record.recorded_at,
                    str(stage_record.evidence_path),
                    stage_record.evidence_sha256,
                    canonical_json(dict(details)),
                ),
            )
            connection.commit()
        except sqlite3.Error as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence stage write failed: "
                + str(error)
            ) from error
        finally:
            connection.close()

    def open_existing_connection(self) -> sqlite3.Connection:
        if not self.journal_path.is_absolute() or not self.journal_path.is_file():
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence journal is missing or not a file"
            )
        try:
            connection = sqlite3.connect(self.journal_path)
            connection.row_factory = sqlite3.Row
            column_names = {
                row["name"]
                for row in connection.execute(
                    "PRAGMA table_info(development_installation_run)"
                )
            }
            if "host_update_handoff_supervisor_launchd_service_label" not in column_names:
                connection.close()
                raise MacOSDevelopmentInstallationEvidenceRunError(
                    "macOS development installation evidence journal does not record "
                    "the C23 Host Update Handoff Supervisor service; evidence runs "
                    "created before this required registration must be restarted"
                )
            return connection
        except MacOSDevelopmentInstallationEvidenceRunError:
            raise
        except sqlite3.Error as error:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence journal cannot be opened: "
                + str(error)
            ) from error


class MacOSDevelopmentInstallationEvidenceRunner:
    """Application workflow for explicit unsigned-development installation evidence."""

    def __init__(self, journal: MacOSDevelopmentInstallationEvidenceJournal):
        self.journal = journal

    def record_artifact_identity(
        self,
    ) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        evidence_run = self.journal.load_evidence_run()
        observed_at = utc_timestamp()
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        identity_observation = (
            macos_host_installation_observation.observe_macos_installer_artifact_identity(
                evidence_run.command_contract.pkgutil_executable,
                evidence_run.installer_artifact_path,
                execute_command=execute_macos_development_installation_command,
            )
        )
        signature_command = execute_macos_development_installation_command(
            evidence_run.command_contract.pkgutil_executable,
            ["--check-signature", str(evidence_run.installer_artifact_path)],
        )
        issue = unsigned_development_package_identity_issue(
            evidence_run,
            identity_observation,
            signature_command,
        )
        details = {
            "purpose": "development-installation",
            "observedInstallerArtifact": observed_artifact,
            "installerArtifactIdentityObservation": (
                macos_host_installation_observation.installer_artifact_identity_document(
                    identity_observation
                )
            ),
            "packageSignatureCommand": (
                macos_host_installation_observation.command_document(signature_command)
            ),
        }
        return self.record_stage(
            evidence_run,
            ARTIFACT_IDENTITY_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            issue,
        )

    def record_clean_host_preflight(
        self,
    ) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(ARTIFACT_IDENTITY_STAGE)
        observed_at = utc_timestamp()
        package_receipt = observe_macos_package_receipt(evidence_run)
        service_observations = observe_required_launchd_service_registrations(
            evidence_run
        )
        issue = clean_host_preflight_issue(package_receipt, service_observations)
        details = {
            "purpose": "development-installation",
            "packageReceiptObservation": (
                macos_host_installation_observation.package_receipt_document(
                    package_receipt
                )
            ),
            "launchdServiceRegistrationObservations": [
                macos_host_installation_observation.launchd_service_registration_document(
                    observation
                )
                for observation in service_observations
            ],
        }
        return self.record_stage(
            evidence_run,
            CLEAN_HOST_PREFLIGHT_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            issue,
        )

    def execute_installation(self) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(CLEAN_HOST_PREFLIGHT_STAGE)
        if os.geteuid() != 0:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development package installation requires a root runner process"
            )
        observed_at = utc_timestamp()
        installer_command = execute_macos_development_installation_command(
            evidence_run.command_contract.installer_executable,
            ["-pkg", str(evidence_run.installer_artifact_path), "-target", "/"],
        )
        package_receipt = observe_macos_package_receipt(evidence_run)
        issue = installation_issue(evidence_run, installer_command, package_receipt)
        details = {
            "purpose": "development-installation",
            "installerCommand": macos_host_installation_observation.command_document(
                installer_command
            ),
            "packageReceiptObservation": (
                macos_host_installation_observation.package_receipt_document(
                    package_receipt
                )
            ),
            "observedInstallerArtifact": observed_installer_artifact(
                evidence_run, observed_at
            ),
        }
        return self.record_stage(
            evidence_run,
            INSTALLATION_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            issue,
        )

    def record_service_registration(
        self,
    ) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(INSTALLATION_STAGE)
        observed_at = utc_timestamp()
        package_receipt = observe_macos_package_receipt(evidence_run)
        service_observations = observe_required_launchd_service_registrations(
            evidence_run
        )
        issue = installed_receipt_or_service_registration_issue(
            evidence_run,
            package_receipt,
            service_observations,
        )
        details = {
            "purpose": "development-installation",
            "packageReceiptObservation": (
                macos_host_installation_observation.package_receipt_document(
                    package_receipt
                )
            ),
            "launchdServiceRegistrationObservations": [
                macos_host_installation_observation.launchd_service_registration_document(
                    observation
                )
                for observation in service_observations
            ],
        }
        return self.record_stage(
            evidence_run,
            SERVICE_REGISTRATION_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            issue,
        )

    def record_supervisor_signature(
        self,
    ) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(SERVICE_REGISTRATION_STAGE)
        observed_at = utc_timestamp()
        signature_observation = observe_macos_ad_hoc_virtual_machine_supervisor_signature(
            evidence_run
        )
        issue = ad_hoc_virtual_machine_supervisor_signature_issue(signature_observation)
        details = {
            "purpose": "development-installation",
            "installedVirtualMachineSupervisorPath": str(
                evidence_run.installed_virtual_machine_supervisor_path
            ),
            "virtualMachineSupervisorCodeSignatureObservation": (
                macos_host_installation_observation.virtual_machine_supervisor_code_signature_document(
                    signature_observation
                )
            ),
        }
        return self.record_stage(
            evidence_run,
            SUPERVISOR_SIGNATURE_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            issue,
        )

    def record_reboot_checkpoint(
        self,
    ) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(SUPERVISOR_SIGNATURE_STAGE)
        observed_at = utc_timestamp()
        boot_session = macos_host_installation_observation.observe_macos_host_boot_session(
            evidence_run.command_contract.sysctl_executable,
            execute_command=execute_macos_development_installation_command,
        )
        return self.record_stage(
            evidence_run,
            REBOOT_CHECKPOINT_STAGE,
            "verified",
            observed_at,
            {
                "purpose": "development-installation",
                "bootSessionObservation": (
                    macos_host_installation_observation.boot_session_document(
                        boot_session
                    )
                ),
            },
            None,
        )

    def record_reboot(self) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        evidence_run = self.require_verified_predecessor(REBOOT_CHECKPOINT_STAGE)
        checkpoint_details = self.journal.load_stage_details(REBOOT_CHECKPOINT_STAGE)
        checkpoint_session_identifier = boot_session_identifier_from_checkpoint(
            checkpoint_details
        )
        observed_at = utc_timestamp()
        boot_session = macos_host_installation_observation.observe_macos_host_boot_session(
            evidence_run.command_contract.sysctl_executable,
            execute_command=execute_macos_development_installation_command,
        )
        package_receipt = observe_macos_package_receipt(evidence_run)
        service_observations = observe_required_launchd_service_registrations(
            evidence_run
        )
        signature_observation = observe_macos_ad_hoc_virtual_machine_supervisor_signature(
            evidence_run
        )
        issue = reboot_persistence_issue(
            evidence_run,
            checkpoint_session_identifier,
            boot_session,
            package_receipt,
            service_observations,
            signature_observation,
        )
        details = {
            "purpose": "development-installation",
            "preRebootBootSessionIdentifier": checkpoint_session_identifier,
            "postRebootBootSessionObservation": (
                macos_host_installation_observation.boot_session_document(boot_session)
            ),
            "packageReceiptObservation": (
                macos_host_installation_observation.package_receipt_document(
                    package_receipt
                )
            ),
            "launchdServiceRegistrationObservations": [
                macos_host_installation_observation.launchd_service_registration_document(
                    observation
                )
                for observation in service_observations
            ],
            "virtualMachineSupervisorCodeSignatureObservation": (
                macos_host_installation_observation.virtual_machine_supervisor_code_signature_document(
                    signature_observation
                )
            ),
        }
        return self.record_stage(
            evidence_run,
            REBOOT_STAGE,
            "verified" if issue is None else "failed",
            observed_at,
            details,
            issue,
        )

    def require_verified_predecessor(
        self,
        predecessor_stage: str,
    ) -> MacOSDevelopmentInstallationEvidenceRun:
        evidence_run = self.journal.load_evidence_run()
        predecessor = self.journal.load_stage_record(predecessor_stage)
        if predecessor is None or predecessor.status != "verified":
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation evidence requires verified predecessor stage: "
                + predecessor_stage
            )
        assert_bound_installer_artifact_is_unchanged(evidence_run)
        return evidence_run

    def record_stage(
        self,
        evidence_run: MacOSDevelopmentInstallationEvidenceRun,
        stage: str,
        status: str,
        observed_at: str,
        details: Mapping[str, Any],
        issue: Mapping[str, str] | None,
    ) -> MacOSDevelopmentInstallationEvidenceStageRecord:
        document = {
            "purpose": "development-installation",
            "runId": evidence_run.run_id,
            "runnerId": evidence_run.runner_id,
            "stage": stage,
            "status": status,
            "recordedAt": observed_at,
            "releaseIdentityReference": release_identity_document(evidence_run),
            "details": dict(details),
        }
        if issue is not None:
            document["issue"] = dict(issue)
        evidence_path, evidence_sha256 = write_new_evidence_document(
            evidence_run.evidence_directory,
            stage,
            document,
        )
        stage_record = MacOSDevelopmentInstallationEvidenceStageRecord(
            stage=stage,
            status=status,
            recorded_at=observed_at,
            evidence_path=evidence_path,
            evidence_sha256=evidence_sha256,
        )
        self.journal.record_new_stage(stage_record, details)
        return stage_record


def create_macos_development_installation_evidence_run(
    *,
    journal_path: Path,
    evidence_directory: Path,
    installer_artifact_path: Path,
    installed_virtual_machine_supervisor_path: Path,
    release_delivery_plans_document: Path,
    release_delivery_plan_id: str,
    run_id: str,
    runner_id: str,
    command_contract: MacOSDevelopmentInstallationCommandContract,
) -> MacOSDevelopmentInstallationEvidenceRun:
    """Bind one unsigned development artifact and C23 identity before effects."""

    validate_evidence_run_input_paths(
        journal_path,
        evidence_directory,
        installer_artifact_path,
        installed_virtual_machine_supervisor_path,
        command_contract,
    )
    try:
        release_plan = load_selected_macos_host_package_release_plan(
            release_delivery_plans_document,
            release_delivery_plan_id,
        )
    except ProductDeliveryReleasePlanError as error:
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation C23 release plan cannot be read: " + str(error)
        ) from error
    evidence_run = evidence_run_from_release_plan(
        release_plan,
        installer_artifact_path,
        installed_virtual_machine_supervisor_path,
        evidence_directory,
        run_id,
        runner_id,
        command_contract,
    )
    if evidence_run.intended_installer_file_name != installer_artifact_path.name:
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installer artifact file name does not match C23"
        )
    MacOSDevelopmentInstallationEvidenceJournal.create_new(journal_path, evidence_run)
    return evidence_run


def evidence_run_from_release_plan(
    release_plan: MacOSHostPackageReleasePlan,
    installer_artifact_path: Path,
    installed_virtual_machine_supervisor_path: Path,
    evidence_directory: Path,
    run_id: str,
    runner_id: str,
    command_contract: MacOSDevelopmentInstallationCommandContract,
) -> MacOSDevelopmentInstallationEvidenceRun:
    return MacOSDevelopmentInstallationEvidenceRun(
        run_id=required_non_empty_string(run_id, "development evidence run ID"),
        runner_id=required_non_empty_string(runner_id, "development evidence runner ID"),
        release_delivery_plan_id=release_plan.release_delivery_plan_id,
        product_version=release_plan.product_version,
        intended_installer_file_name=release_plan.expected_package_file_name,
        macos_installer_package_identifier=release_plan.macos_installer_package_identifier,
        host_agent_launchd_service_label=release_plan.host_agent_launchd_service_label,
        host_edge_proxy_launchd_service_label=(
            release_plan.host_edge_proxy_launchd_service_label
        ),
        host_update_handoff_supervisor_launchd_service_label=(
            release_plan.host_update_handoff_supervisor_launchd_service_label
        ),
        installed_virtual_machine_supervisor_path=installed_virtual_machine_supervisor_path,
        installer_artifact_path=installer_artifact_path,
        bound_installer_artifact_sha256=sha256_file(installer_artifact_path),
        evidence_directory=evidence_directory,
        command_contract=command_contract,
        created_at=utc_timestamp(),
    )


def validate_evidence_run_input_paths(
    journal_path: Path,
    evidence_directory: Path,
    installer_artifact_path: Path,
    installed_virtual_machine_supervisor_path: Path,
    command_contract: MacOSDevelopmentInstallationCommandContract,
) -> None:
    if not journal_path.is_absolute():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence journal path must be absolute"
        )
    if not evidence_directory.is_absolute() or not evidence_directory.is_dir():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence directory is missing or not an absolute directory"
        )
    if not installer_artifact_path.is_absolute() or not installer_artifact_path.is_file():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installer artifact is missing or not an absolute file"
        )
    if not installed_virtual_machine_supervisor_path.is_absolute():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "installed macOS virtual machine supervisor path must be absolute"
        )
    validate_command_contract(command_contract)


def validate_new_journal_path(journal_path: Path) -> None:
    if not journal_path.is_absolute() or journal_path.exists():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence journal path must be new and absolute"
        )
    if not journal_path.parent.is_dir():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence journal parent directory is missing"
        )


def validate_command_contract(
    command_contract: MacOSDevelopmentInstallationCommandContract,
) -> None:
    for name, executable in (
        ("pkgutil", command_contract.pkgutil_executable),
        ("installer", command_contract.installer_executable),
        ("launchctl", command_contract.launchctl_executable),
        ("codesign", command_contract.codesign_executable),
        ("sysctl", command_contract.sysctl_executable),
    ):
        if not executable.is_absolute() or not executable.is_file():
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "macOS development installation command contract "
                + name
                + " executable is missing or not an absolute file"
            )


def command_contract_document(
    command_contract: MacOSDevelopmentInstallationCommandContract,
) -> Mapping[str, str]:
    return {
        "pkgutilExecutable": str(command_contract.pkgutil_executable),
        "installerExecutable": str(command_contract.installer_executable),
        "launchctlExecutable": str(command_contract.launchctl_executable),
        "codesignExecutable": str(command_contract.codesign_executable),
        "sysctlExecutable": str(command_contract.sysctl_executable),
    }


def command_contract_from_journal_document(
    document: Any,
) -> MacOSDevelopmentInstallationCommandContract:
    if not isinstance(document, dict):
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation command contract must be an object"
        )
    return MacOSDevelopmentInstallationCommandContract(
        pkgutil_executable=Path(
            required_non_empty_string(
                document.get("pkgutilExecutable"), "journal pkgutil executable"
            )
        ),
        installer_executable=Path(
            required_non_empty_string(
                document.get("installerExecutable"), "journal installer executable"
            )
        ),
        launchctl_executable=Path(
            required_non_empty_string(
                document.get("launchctlExecutable"), "journal launchctl executable"
            )
        ),
        codesign_executable=Path(
            required_non_empty_string(
                document.get("codesignExecutable"), "journal codesign executable"
            )
        ),
        sysctl_executable=Path(
            required_non_empty_string(
                document.get("sysctlExecutable"), "journal sysctl executable"
            )
        ),
    )


def assert_bound_installer_artifact_is_unchanged(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
) -> None:
    current_sha256 = sha256_file(evidence_run.installer_artifact_path)
    if current_sha256 != evidence_run.bound_installer_artifact_sha256:
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "bound macOS development installer artifact SHA-256 changed after evidence run creation"
        )


def observed_installer_artifact(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
    observed_at: str,
) -> Mapping[str, str]:
    assert_bound_installer_artifact_is_unchanged(evidence_run)
    return {
        "kind": "pkg",
        "fileName": evidence_run.intended_installer_file_name,
        "productVersion": evidence_run.product_version,
        "sha256": evidence_run.bound_installer_artifact_sha256,
        "observedAt": observed_at,
    }


def execute_macos_development_installation_command(
    executable: Path,
    arguments: Sequence[str],
) -> macos_host_installation_observation.MacOSHostInstallationCommandObservation:
    try:
        return macos_host_installation_observation.execute_macos_host_installation_command(
            executable,
            arguments,
        )
    except macos_host_installation_observation.MacOSHostInstallationObservationError as error:
        raise MacOSDevelopmentInstallationEvidenceRunError(str(error)) from error


def unsigned_development_package_identity_issue(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
    identity_observation: macos_host_installation_observation.MacOSInstallerArtifactIdentityObservation,
    signature_command: macos_host_installation_observation.MacOSHostInstallationCommandObservation,
) -> Mapping[str, str] | None:
    if identity_observation.state != "available":
        return {
            "code": "macos-development-package-metadata-unavailable",
            "message": "pkgutil could not provide readable metadata for the selected development installer artifact.",
        }
    if identity_observation.package_identifier != evidence_run.macos_installer_package_identifier:
        return {
            "code": "macos-development-package-identifier-mismatch",
            "message": "Selected development installer package metadata identifier does not match C23.",
        }
    if identity_observation.product_version != evidence_run.product_version:
        return {
            "code": "macos-development-package-version-mismatch",
            "message": "Selected development installer package metadata version does not match C23.",
        }
    signature_output = (signature_command.stdout + "\n" + signature_command.stderr).lower()
    # macOS pkgutil explicitly reports an unsigned flat package as
    # ``Status: no signature`` and returns exit status 1.  The status line is
    # the external owner's explicit signature fact; the non-zero code remains
    # raw evidence but does not erase that fact.  Any other non-zero result is
    # still unavailable rather than being interpreted as unsigned.
    if "status: no signature" in signature_output:
        return None
    if signature_command.returncode != 0:
        return {
            "code": "macos-development-package-signature-observation-failed",
            "message": "pkgutil could not observe the selected development package signature state.",
        }
    return {
        "code": "macos-development-package-is-not-unsigned",
        "message": "The selected development installer package must explicitly report Status: no signature.",
    }


def observe_macos_package_receipt(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
) -> macos_host_installation_observation.MacOSPackageReceiptObservation:
    return macos_host_installation_observation.observe_macos_package_receipt(
        evidence_run.command_contract.pkgutil_executable,
        evidence_run.macos_installer_package_identifier,
        execute_command=execute_macos_development_installation_command,
    )


def observe_required_launchd_service_registrations(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
) -> tuple[macos_host_installation_observation.MacOSLaunchdServiceRegistrationObservation, ...]:
    return (
        macos_host_installation_observation.observe_macos_launchd_service_registration(
            evidence_run.command_contract.launchctl_executable,
            "host-agent",
            evidence_run.host_agent_launchd_service_label,
            execute_command=execute_macos_development_installation_command,
        ),
        macos_host_installation_observation.observe_macos_launchd_service_registration(
            evidence_run.command_contract.launchctl_executable,
            "host-edge-proxy",
            evidence_run.host_edge_proxy_launchd_service_label,
            execute_command=execute_macos_development_installation_command,
        ),
        macos_host_installation_observation.observe_macos_launchd_service_registration(
            evidence_run.command_contract.launchctl_executable,
            "host-update-handoff-supervisor",
            evidence_run.host_update_handoff_supervisor_launchd_service_label,
            execute_command=execute_macos_development_installation_command,
        ),
    )


def observe_macos_ad_hoc_virtual_machine_supervisor_signature(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
) -> macos_host_installation_observation.MacOSVirtualMachineSupervisorCodeSignatureObservation:
    return macos_host_installation_observation.observe_macos_virtual_machine_supervisor_code_signature(
        evidence_run.command_contract.codesign_executable,
        evidence_run.installed_virtual_machine_supervisor_path,
        execute_command=execute_macos_development_installation_command,
    )


def clean_host_preflight_issue(
    package_receipt: macos_host_installation_observation.MacOSPackageReceiptObservation,
    service_observations: Sequence[
        macos_host_installation_observation.MacOSLaunchdServiceRegistrationObservation
    ],
) -> Mapping[str, str] | None:
    if package_receipt.state == "installed":
        return {
            "code": "macos-development-host-package-receipt-already-installed",
            "message": "The C23 macOS installer receipt is already installed, so this Host is not clean for this development run.",
        }
    if package_receipt.state != "absent":
        return {
            "code": "macos-development-host-package-receipt-observation-unavailable",
            "message": "The C23 macOS installer receipt absence could not be observed explicitly.",
        }
    for observation in service_observations:
        if observation.state == "registered":
            return {
                "code": "macos-development-host-service-already-registered",
                "message": "A C23-required launchd service is already registered, so this Host is not clean for this development run.",
            }
        if observation.state != "absent":
            return {
                "code": "macos-development-host-service-observation-unavailable",
                "message": "A C23-required launchd service absence could not be observed explicitly.",
            }
    return None


def installation_issue(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
    installer_command: macos_host_installation_observation.MacOSHostInstallationCommandObservation,
    package_receipt: macos_host_installation_observation.MacOSPackageReceiptObservation,
) -> Mapping[str, str] | None:
    if installer_command.returncode != 0:
        return {
            "code": "macos-development-installation-command-failed",
            "message": "macOS installer returned a non-zero result for the selected development package.",
        }
    return installed_package_receipt_issue(evidence_run, package_receipt)


def installed_receipt_or_service_registration_issue(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
    package_receipt: macos_host_installation_observation.MacOSPackageReceiptObservation,
    service_observations: Sequence[
        macos_host_installation_observation.MacOSLaunchdServiceRegistrationObservation
    ],
) -> Mapping[str, str] | None:
    receipt_issue = installed_package_receipt_issue(evidence_run, package_receipt)
    if receipt_issue is not None:
        return receipt_issue
    for observation in service_observations:
        if observation.state != "registered":
            return {
                "code": "macos-development-launchd-service-registration-not-observed",
                "message": "A C23-required launchd service was not observed as registered.",
            }
    return None


def installed_package_receipt_issue(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
    package_receipt: macos_host_installation_observation.MacOSPackageReceiptObservation,
) -> Mapping[str, str] | None:
    if package_receipt.state != "installed":
        return {
            "code": "macos-development-installed-package-receipt-not-observed",
            "message": "The C23 macOS installer receipt was not observed as installed after the installer effect.",
        }
    if package_receipt.package_identifier != evidence_run.macos_installer_package_identifier:
        return {
            "code": "macos-development-installed-package-receipt-identifier-mismatch",
            "message": "The observed macOS installer receipt identifier does not match C23.",
        }
    if package_receipt.product_version != evidence_run.product_version:
        return {
            "code": "macos-development-installed-package-receipt-version-mismatch",
            "message": "The observed macOS installer receipt version does not match C23.",
        }
    return None


def ad_hoc_virtual_machine_supervisor_signature_issue(
    observation: macos_host_installation_observation.MacOSVirtualMachineSupervisorCodeSignatureObservation,
) -> Mapping[str, str] | None:
    if observation.signature_state != "ad-hoc":
        return {
            "code": "macos-development-supervisor-signature-not-ad-hoc",
            "message": "The installed macOS virtual machine supervisor was not observed with an ad-hoc code signature.",
        }
    if observation.virtualization_entitlement_state != "present":
        return {
            "code": "macos-development-supervisor-virtualization-entitlement-not-observed",
            "message": "The installed macOS virtual machine supervisor did not expose com.apple.security.virtualization=true.",
        }
    return None


def reboot_persistence_issue(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
    checkpoint_session_identifier: str,
    current_boot_session: macos_host_installation_observation.MacOSHostBootSessionObservation,
    package_receipt: macos_host_installation_observation.MacOSPackageReceiptObservation,
    service_observations: Sequence[
        macos_host_installation_observation.MacOSLaunchdServiceRegistrationObservation
    ],
    signature_observation: macos_host_installation_observation.MacOSVirtualMachineSupervisorCodeSignatureObservation,
) -> Mapping[str, str] | None:
    if current_boot_session.boot_session_identifier == checkpoint_session_identifier:
        return {
            "code": "macos-development-reboot-not-observed",
            "message": "The macOS boot-session identifier did not change after the development reboot checkpoint.",
        }
    installation_issue_value = installed_receipt_or_service_registration_issue(
        evidence_run,
        package_receipt,
        service_observations,
    )
    if installation_issue_value is not None:
        return installation_issue_value
    return ad_hoc_virtual_machine_supervisor_signature_issue(signature_observation)


def boot_session_identifier_from_checkpoint(checkpoint_details: Mapping[str, Any]) -> str:
    boot_session = checkpoint_details.get("bootSessionObservation")
    if not isinstance(boot_session, dict):
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development reboot checkpoint has no boot-session observation"
        )
    return required_non_empty_string(
        boot_session.get("bootSessionIdentifier"),
        "macOS development reboot checkpoint boot-session identifier",
    )


def release_identity_document(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
) -> Mapping[str, str]:
    return {
        "releaseDeliveryPlanId": evidence_run.release_delivery_plan_id,
        "productVersion": evidence_run.product_version,
        "intendedInstallerFileName": evidence_run.intended_installer_file_name,
        "macOSInstallerPackageIdentifier": (
            evidence_run.macos_installer_package_identifier
        ),
        "hostAgentLaunchdServiceLabel": evidence_run.host_agent_launchd_service_label,
        "hostEdgeProxyLaunchdServiceLabel": (
            evidence_run.host_edge_proxy_launchd_service_label
        ),
        "hostUpdateHandoffSupervisorLaunchdServiceLabel": (
            evidence_run.host_update_handoff_supervisor_launchd_service_label
        ),
        "boundInstallerArtifactSHA256": evidence_run.bound_installer_artifact_sha256,
    }


def write_new_evidence_document(
    evidence_directory: Path,
    stage: str,
    evidence_document: Mapping[str, Any],
) -> tuple[Path, str]:
    validate_development_installation_stage(stage)
    if not evidence_directory.is_absolute() or not evidence_directory.is_dir():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence directory is missing or not an absolute directory"
        )
    evidence_path = evidence_directory / (stage + ".json")
    if evidence_path.exists():
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence document already exists for stage: "
            + stage
        )
    document_bytes = (canonical_json(evidence_document) + "\n").encode("utf-8")
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=evidence_directory,
            prefix="." + stage + ".",
            delete=False,
        ) as temporary_file:
            temporary_file.write(document_bytes)
            temporary_path = Path(temporary_file.name)
        os.replace(temporary_path, evidence_path)
    except OSError as error:
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence document write failed: " + str(error)
        ) from error
    return evidence_path, sha256_file(evidence_path)


def validate_development_installation_stage(stage: str) -> None:
    if stage not in DEVELOPMENT_INSTALLATION_STAGES:
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "unknown macOS development installation evidence stage: " + stage
        )


def required_non_empty_string(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise MacOSDevelopmentInstallationEvidenceRunError(name + " must be non-empty")
    return value


def required_sha256(value: Any, name: str) -> str:
    if not isinstance(value, str) or len(value) != 64:
        raise MacOSDevelopmentInstallationEvidenceRunError(name + " must be SHA-256")
    try:
        int(value, 16)
    except ValueError as error:
        raise MacOSDevelopmentInstallationEvidenceRunError(name + " must be SHA-256") from error
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as artifact:
            for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installer artifact cannot be read: " + str(error)
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
        raise MacOSDevelopmentInstallationEvidenceRunError(
            "macOS development installation evidence runner requires a Darwin Host"
        )


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)

    create_run = subcommands.add_parser(
        "create-run", help="create a new explicit development installation journal"
    )
    create_run.add_argument("--journal-path", required=True)
    create_run.add_argument("--evidence-directory", required=True)
    create_run.add_argument("--installer-artifact", required=True)
    create_run.add_argument("--installed-virtual-machine-supervisor", required=True)
    create_run.add_argument("--release-delivery-plans-document", required=True)
    create_run.add_argument("--release-delivery-plan-id", required=True)
    create_run.add_argument("--run-id", required=True)
    create_run.add_argument("--runner-id", required=True)
    create_run.add_argument("--pkgutil-executable", required=True)
    create_run.add_argument("--installer-executable", required=True)
    create_run.add_argument("--launchctl-executable", required=True)
    create_run.add_argument("--codesign-executable", required=True)
    create_run.add_argument("--sysctl-executable", required=True)

    for command_name in (
        "record-artifact-identity",
        "record-clean-host-preflight",
        "record-service-registration",
        "record-supervisor-signature",
        "record-reboot-checkpoint",
        "record-reboot",
    ):
        command = subcommands.add_parser(command_name)
        command.add_argument("--journal-path", required=True)

    installation = subcommands.add_parser("execute-installation")
    installation.add_argument("--journal-path", required=True)
    installation.add_argument(
        "--authorize-development-installation",
        action="store_true",
        help="explicitly authorize the irreversible macOS Installer effect",
    )
    return parser.parse_args(arguments)


def main(arguments: Sequence[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        if parsed.command == "create-run":
            evidence_run = create_macos_development_installation_evidence_run(
                journal_path=Path(parsed.journal_path),
                evidence_directory=Path(parsed.evidence_directory),
                installer_artifact_path=Path(parsed.installer_artifact),
                installed_virtual_machine_supervisor_path=Path(
                    parsed.installed_virtual_machine_supervisor
                ),
                release_delivery_plans_document=Path(
                    parsed.release_delivery_plans_document
                ),
                release_delivery_plan_id=parsed.release_delivery_plan_id,
                run_id=parsed.run_id,
                runner_id=parsed.runner_id,
                command_contract=MacOSDevelopmentInstallationCommandContract(
                    pkgutil_executable=Path(parsed.pkgutil_executable),
                    installer_executable=Path(parsed.installer_executable),
                    launchctl_executable=Path(parsed.launchctl_executable),
                    codesign_executable=Path(parsed.codesign_executable),
                    sysctl_executable=Path(parsed.sysctl_executable),
                ),
            )
            print(canonical_json({"evidenceRun": evidence_run_document(evidence_run)}))
            return 0

        require_macos_host_platform()
        runner = MacOSDevelopmentInstallationEvidenceRunner(
            MacOSDevelopmentInstallationEvidenceJournal(Path(parsed.journal_path))
        )
        if parsed.command == "record-artifact-identity":
            stage_record = runner.record_artifact_identity()
        elif parsed.command == "record-clean-host-preflight":
            stage_record = runner.record_clean_host_preflight()
        elif parsed.command == "execute-installation":
            if not parsed.authorize_development_installation:
                raise MacOSDevelopmentInstallationEvidenceRunError(
                    "execute-installation requires --authorize-development-installation"
                )
            stage_record = runner.execute_installation()
        elif parsed.command == "record-service-registration":
            stage_record = runner.record_service_registration()
        elif parsed.command == "record-supervisor-signature":
            stage_record = runner.record_supervisor_signature()
        elif parsed.command == "record-reboot-checkpoint":
            stage_record = runner.record_reboot_checkpoint()
        elif parsed.command == "record-reboot":
            stage_record = runner.record_reboot()
        else:
            raise MacOSDevelopmentInstallationEvidenceRunError(
                "unknown macOS development installation evidence command"
            )
        print(canonical_json(stage_record_document(stage_record)))
        return 0
    except MacOSDevelopmentInstallationEvidenceRunError as error:
        print("macOS development installation evidence failed: " + str(error), file=sys.stderr)
        return 1


def stage_record_document(
    stage_record: MacOSDevelopmentInstallationEvidenceStageRecord,
) -> Mapping[str, str]:
    return {
        "stage": stage_record.stage,
        "status": stage_record.status,
        "recordedAt": stage_record.recorded_at,
        "evidencePath": str(stage_record.evidence_path),
        "evidenceSHA256": stage_record.evidence_sha256,
    }


def evidence_run_document(
    evidence_run: MacOSDevelopmentInstallationEvidenceRun,
) -> Mapping[str, Any]:
    document = asdict(evidence_run)
    document["installed_virtual_machine_supervisor_path"] = str(
        evidence_run.installed_virtual_machine_supervisor_path
    )
    document["installer_artifact_path"] = str(evidence_run.installer_artifact_path)
    document["evidence_directory"] = str(evidence_run.evidence_directory)
    document["command_contract"] = command_contract_document(
        evidence_run.command_contract
    )
    return document


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
