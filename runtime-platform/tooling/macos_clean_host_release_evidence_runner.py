#!/usr/bin/env python3
"""Collect explicit macOS clean-Host C24 release-delivery evidence.

This Release-process tool owns only one ``MacOSCleanHostReleaseEvidenceRun``
and its SQLite journal.  It does not own Host Agent, Guest Runtime, launchd,
or installer state.  Those facts are observed through explicitly configured
macOS command-line contracts and then written as evidence documents plus C24
proof fragments.

The runner intentionally separates these operations:

* artifact integrity observes the selected PKG identity and exact C23
  signature policy (unsigned or Developer ID);
* clean-Host preflight observes that the C23 receipt and launchd registrations
  are absent before installation;
* clean installation performs ``installer`` only with an explicit CLI grant;
* service registration observes each C23-named launchd service after install;
* reboot uses a durable boot-session checkpoint and never reboots a Host by
  itself.
* installed Guest runtime evidence attaches the exact verified C78 first-boot,
  direct-upload lineage, and post-reboot documents as a separate C24 stage.

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
import sys
import tempfile
from typing import Any, Mapping, Sequence

from tooling import host_platform_release_transition_evidence
from tooling import macos_host_installation_observation
from tooling.contracts import ContractRepository, ContractToolError
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
INSTALLED_GUEST_RUNTIME_STAGE = "installed-guest-runtime"
UPDATE_STAGE = "update"
ROLLBACK_STAGE = "rollback"
UNINSTALL_REINSTALL_STAGE = "uninstall-reinstall"

C24_PROOF_STAGES = (
    ARTIFACT_INTEGRITY_STAGE,
    CLEAN_INSTALL_STAGE,
    SERVICE_REGISTRATION_STAGE,
    REBOOT_STAGE,
    INSTALLED_GUEST_RUNTIME_STAGE,
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
    INSTALLED_GUEST_RUNTIME_STAGE,
    UPDATE_STAGE,
    ROLLBACK_STAGE,
    UNINSTALL_REINSTALL_STAGE,
}

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
    macos_installer_signature_policy: str
    host_agent_launchd_service_label: str
    host_edge_proxy_launchd_service_label: str
    host_update_handoff_supervisor_launchd_service_label: str
    installer_artifact_path: Path
    bound_installer_artifact_sha256: str
    evidence_directory: Path
    command_contract: MacOSCleanHostReleaseEvidenceCommandContract
    created_at: str


# These aliases preserve the release workflow's domain-facing vocabulary while
# keeping command observation in the adapter that owns parsing external output.
# The release runner still owns only C24 policy, journal transitions, and proof
# composition; it supplies its own command executor so its command evidence
# remains release-run scoped and testable.
MacOSCleanHostReleaseEvidenceCommandObservation = (
    macos_host_installation_observation.MacOSHostInstallationCommandObservation
)
MacOSPackageReceiptObservation = (
    macos_host_installation_observation.MacOSPackageReceiptObservation
)
MacOSInstallerArtifactReleaseIdentityObservation = (
    macos_host_installation_observation.MacOSInstallerArtifactIdentityObservation
)
MacOSLaunchdServiceRegistrationObservation = (
    macos_host_installation_observation.MacOSLaunchdServiceRegistrationObservation
)
MacOSHostBootSessionObservation = (
    macos_host_installation_observation.MacOSHostBootSessionObservation
)


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
            connection = sqlite3.connect(journal_path)
            try:
                connection.executescript(
                    """
                    CREATE TABLE evidence_run (
                        run_id TEXT PRIMARY KEY,
                        runner_id TEXT NOT NULL,
                        release_delivery_plan_id TEXT NOT NULL,
                        product_version TEXT NOT NULL,
                        intended_installer_file_name TEXT NOT NULL,
                        macos_installer_package_identifier TEXT NOT NULL,
                        macos_installer_signature_policy TEXT NOT NULL,
                        host_agent_launchd_service_label TEXT NOT NULL,
                        host_edge_proxy_launchd_service_label TEXT NOT NULL,
                        host_update_handoff_supervisor_launchd_service_label TEXT NOT NULL,
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
                        macos_installer_signature_policy,
                        host_agent_launchd_service_label,
                        host_edge_proxy_launchd_service_label,
                        host_update_handoff_supervisor_launchd_service_label,
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
                        evidence_run.macos_installer_signature_policy,
                        evidence_run.host_agent_launchd_service_label,
                        evidence_run.host_edge_proxy_launchd_service_label,
                        evidence_run.host_update_handoff_supervisor_launchd_service_label,
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
                connection.commit()
            finally:
                connection.close()
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
            macos_installer_signature_policy=required_macos_installer_signature_policy(
                row["macos_installer_signature_policy"],
                "journal macOS installer signature policy",
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
            column_names = {
                row["name"]
                for row in connection.execute("PRAGMA table_info(evidence_run)")
            }
            required_columns = {
                "host_update_handoff_supervisor_launchd_service_label",
                "macos_installer_signature_policy",
            }
            if not required_columns.issubset(column_names):
                connection.close()
                raise MacOSCleanHostReleaseEvidenceRunError(
                    "macOS clean-Host release evidence journal does not record every "
                    "required C23 service/signature-policy fact; evidence runs created "
                    "before those facts must be restarted"
                )
            return connection
        except MacOSCleanHostReleaseEvidenceRunError:
            raise
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

    def record_installed_guest_runtime(
        self,
        contract_root: Path,
        first_boot_evidence_path: Path,
        direct_upload_evidence_path: Path,
        post_reboot_evidence_path: Path,
    ) -> MacOSCleanHostReleaseEvidenceStageRecord:
        """Attach one complete verified C78 chain after the observed Host reboot."""

        evidence_run = self.require_verified_predecessor(REBOOT_STAGE)
        observed_at = utc_timestamp()
        details, observed_issue = observe_installed_guest_runtime_evidence(
            evidence_run,
            contract_root,
            first_boot_evidence_path,
            direct_upload_evidence_path,
            post_reboot_evidence_path,
        )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        details = {
            **details,
            "observedInstallerArtifact": observed_artifact,
        }
        return self.record_stage_with_c24_proof(
            evidence_run,
            INSTALLED_GUEST_RUNTIME_STAGE,
            "verified" if observed_issue is None else "failed",
            observed_at,
            details,
            compose_verified_c24_proof(
                evidence_run,
                INSTALLED_GUEST_RUNTIME_STAGE,
                observed_at,
                observed_artifact,
            )
            if observed_issue is None
            else compose_failed_c24_proof(
                evidence_run,
                INSTALLED_GUEST_RUNTIME_STAGE,
                observed_at,
                observed_issue,
            ),
            observed_issue,
        )

    def record_host_platform_update(
        self,
        release_delivery_plans_document: Path,
        host_update_journal_path: Path,
        host_platform_effect_receipt_path: Path,
        host_installation_manifest_path: Path,
        host_installation_footprint_path: Path,
    ) -> MacOSCleanHostReleaseEvidenceStageRecord:
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
    ) -> MacOSCleanHostReleaseEvidenceStageRecord:
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
    ) -> MacOSCleanHostReleaseEvidenceStageRecord:
        """Join C29/C28/C55/C48/C49 facts with fresh native observations."""

        other_transition_stage = (
            ROLLBACK_STAGE if stage == UPDATE_STAGE else UPDATE_STAGE
        )
        if self.journal.load_stage_record(other_transition_stage) is not None:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host release evidence run cannot mix update and rollback "
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
        package_receipt = observe_macos_package_receipt(
            evidence_run.command_contract.pkgutil_executable,
            evidence_run.macos_installer_package_identifier,
        )
        service_observations = observe_required_launchd_service_registrations(
            evidence_run.command_contract.launchctl_executable,
            evidence_run,
        )
        if issue is None and transition is not None:
            issue = host_platform_transition_os_issue(
                stage, evidence_run, transition, package_receipt, service_observations
            )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        details: dict[str, Any] = {
            "packageReceiptObservation": package_receipt_document(package_receipt),
            "launchdServiceRegistrationObservations": [
                launchd_service_registration_document(observation)
                for observation in service_observations
            ],
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
        host_installation_manager_path: Path,
        installed_manifest_path: Path,
        installation_journal_path: Path,
        installation_receipt_path: Path,
        removal_journal_path: Path,
        removal_receipt_path: Path,
        removal_request_id: str,
        expected_installation_id: str,
        expected_release_id: str,
    ) -> MacOSCleanHostReleaseEvidenceStageRecord:
        """Prove C54 preservation removal and one fresh installation.

        Every lifecycle path and identity is supplied by the release operator.
        The runner never derives a current release, a mutable-data location, or
        a removal receipt from the installed package layout.  C54 owns the
        removal effect and writes the durable receipt; this release workflow
        only invokes the declared manager and observes the resulting macOS
        package/service facts before it allows a reinstall.
        """

        evidence_run = self.require_verified_predecessor(REBOOT_STAGE)
        if os.geteuid() != 0:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS clean-Host uninstall/reinstall requires a root runner process"
            )
        validate_macos_preserving_removal_inputs(
            host_installation_manager_path,
            installed_manifest_path,
            installation_journal_path,
            installation_receipt_path,
            removal_journal_path,
            removal_receipt_path,
            removal_request_id,
            expected_installation_id,
            expected_release_id,
        )
        observed_at = utc_timestamp()
        removal_command = execute_macos_clean_host_command(
            host_installation_manager_path,
            [
                "--mode",
                "remove",
                "--manifest",
                str(installed_manifest_path),
                "--journal",
                str(installation_journal_path),
                "--receipt",
                str(installation_receipt_path),
                "--request-id",
                removal_request_id,
                "--installation-id",
                expected_installation_id,
                "--release-id",
                expected_release_id,
                "--data-disposition",
                "preserve-mutable-data",
                "--removal-journal",
                str(removal_journal_path),
                "--removal-receipt",
                str(removal_receipt_path),
                "--pkgutil",
                str(evidence_run.command_contract.pkgutil_executable),
                "--launchctl",
                str(evidence_run.command_contract.launchctl_executable),
            ],
        )
        removal_receipt, removal_receipt_sha256, removal_receipt_issue = (
            observe_completed_macos_preservation_removal_receipt(
                removal_receipt_path,
                expected_installation_id,
                expected_release_id,
            )
        )
        removal_package_receipt = observe_macos_package_receipt(
            evidence_run.command_contract.pkgutil_executable,
            evidence_run.macos_installer_package_identifier,
        )
        removal_service_observations = observe_required_launchd_service_registrations(
            evidence_run.command_contract.launchctl_executable,
            evidence_run,
        )
        removal_issue = macos_preserving_removal_issue(
            removal_command,
            removal_receipt_issue,
            removal_package_receipt,
            removal_service_observations,
        )
        observed_artifact = observed_installer_artifact(evidence_run, observed_at)
        removal_details: dict[str, Any] = {
            "dataDisposition": "preserve-mutable-data",
            "hostInstallationManagerCommand": command_document(removal_command),
            "packageReceiptObservation": package_receipt_document(
                removal_package_receipt
            ),
            "launchdServiceRegistrationObservations": [
                launchd_service_registration_document(observation)
                for observation in removal_service_observations
            ],
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

        reinstall_command = execute_macos_clean_host_command(
            evidence_run.command_contract.installer_executable,
            ["-pkg", str(evidence_run.installer_artifact_path), "-target", "/"],
        )
        reinstall_package_receipt = observe_macos_package_receipt(
            evidence_run.command_contract.pkgutil_executable,
            evidence_run.macos_installer_package_identifier,
        )
        reinstall_service_observations = observe_required_launchd_service_registrations(
            evidence_run.command_contract.launchctl_executable,
            evidence_run,
        )
        reinstall_issue = macos_reinstall_after_preserving_removal_issue(
            evidence_run,
            reinstall_command,
            reinstall_package_receipt,
            reinstall_service_observations,
        )
        details = {
            **removal_details,
            "reinstallCommand": command_document(reinstall_command),
            "postReinstall": {
                "packageReceiptObservation": package_receipt_document(
                    reinstall_package_receipt
                ),
                "launchdServiceRegistrationObservations": [
                    launchd_service_registration_document(observation)
                    for observation in reinstall_service_observations
                ],
            },
            "observedInstallerArtifact": observed_artifact,
        }
        return self.record_stage_with_c24_proof(
            evidence_run,
            UNINSTALL_REINSTALL_STAGE,
            "verified" if reinstall_issue is None else "failed",
            observed_at,
            details,
            compose_verified_c24_proof(
                evidence_run,
                UNINSTALL_REINSTALL_STAGE,
                observed_at,
                observed_artifact,
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
        macos_installer_signature_policy=(
            release_plan.macos_installer_signature_policy
        ),
        host_agent_launchd_service_label=(
            release_plan.host_agent_launchd_service_label
        ),
        host_edge_proxy_launchd_service_label=(
            release_plan.host_edge_proxy_launchd_service_label
        ),
        host_update_handoff_supervisor_launchd_service_label=(
            release_plan.host_update_handoff_supervisor_launchd_service_label
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


def required_macos_installer_signature_policy(value: Any, field: str) -> str:
    policy = required_non_empty_string(value, field)
    if policy not in {"unsigned", "developer-id"}:
        raise MacOSCleanHostReleaseEvidenceRunError(
            field + " must be unsigned or developer-id"
        )
    return policy


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
        return macos_host_installation_observation.execute_macos_host_installation_command(
            executable,
            arguments,
        )
    except macos_host_installation_observation.MacOSHostInstallationObservationError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host command execution failed: " + str(error)
        ) from error


def observe_macos_installer_artifact_release_identity(
    pkgutil_executable: Path,
    installer_artifact_path: Path,
) -> MacOSInstallerArtifactReleaseIdentityObservation:
    """Observe flat-PKG identity without allowing filename-derived identity."""

    return macos_host_installation_observation.observe_macos_installer_artifact_identity(
        pkgutil_executable,
        installer_artifact_path,
        execute_command=execute_macos_clean_host_command,
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
    signature_output = (
        package_signature_command.stdout + "\n" + package_signature_command.stderr
    ).lower()
    if evidence_run.macos_installer_signature_policy == "unsigned":
        # macOS pkgutil explicitly reports an unsigned flat package as
        # ``Status: no signature`` and may return non-zero. The reported
        # status—not the return code—is the external owner fact that C23 asks
        # this release run to observe. Any other result remains a failure.
        if "status: no signature" in signature_output:
            return None
        return {
            "code": "macos-package-unsigned-signature-state-not-observed",
            "message": "The selected macOS installer artifact does not explicitly report the C23 unsigned signature state.",
        }
    if package_signature_command.returncode != 0:
        return {
            "code": "macos-package-signature-check-failed",
            "message": "pkgutil signature verification failed for the selected macOS installer artifact.",
        }
    if "status: signed" not in signature_output or "no signature" in signature_output:
        return {
            "code": "macos-package-signature-not-accepted",
            "message": "The selected macOS installer artifact does not report the C23 accepted Developer ID signature state.",
        }
    return None


def observe_macos_package_receipt(
    pkgutil_executable: Path, package_identifier: str
) -> MacOSPackageReceiptObservation:
    return macos_host_installation_observation.observe_macos_package_receipt(
        pkgutil_executable,
        package_identifier,
        execute_command=execute_macos_clean_host_command,
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
        observe_macos_launchd_service_registration(
            launchctl_executable,
            "host-update-handoff-supervisor",
            evidence_run.host_update_handoff_supervisor_launchd_service_label,
        ),
    )


def observe_macos_launchd_service_registration(
    launchctl_executable: Path, role: str, service_label: str
) -> MacOSLaunchdServiceRegistrationObservation:
    return macos_host_installation_observation.observe_macos_launchd_service_registration(
        launchctl_executable,
        role,
        service_label,
        execute_command=execute_macos_clean_host_command,
    )


def observe_macos_host_boot_session(
    sysctl_executable: Path,
) -> MacOSHostBootSessionObservation:
    try:
        return macos_host_installation_observation.observe_macos_host_boot_session(
            sysctl_executable,
            execute_command=execute_macos_clean_host_command,
        )
    except macos_host_installation_observation.MacOSHostInstallationObservationError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host boot session identifier is unavailable: " + str(error)
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


def observe_host_platform_transition(
    stage: str,
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    release_delivery_plans_document: Path,
    host_update_journal_path: Path,
    host_platform_effect_receipt_path: Path,
    host_installation_manifest_path: Path,
    host_installation_footprint_path: Path,
) -> tuple[
    host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence | None,
    Mapping[str, str] | None,
]:
    """Read the explicit transition contract without treating it as C24 proof."""

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
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS Host Platform transition stage is unsupported: " + stage
            )
    except host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidenceError as error:
        return None, {
            "code": "macos-host-platform-" + stage + "-transition-invalid",
            "message": "C29/C28/C55/C48/C49 transition evidence is invalid: " + str(error),
        }
    if (
        transition.release_delivery_plan_id != evidence_run.release_delivery_plan_id
        or transition.platform != "macos"
        or transition.provider_kind != "macos-virtualization"
        or transition.target_product_version != evidence_run.product_version
        or transition.observed_package_identifier
        != evidence_run.macos_installer_package_identifier
    ):
        return None, {
            "code": "macos-host-platform-" + stage + "-transition-identity-mismatch",
            "message": "C29/C28/C55/C48/C49 transition evidence does not match this macOS C24 evidence run.",
        }
    return transition, None


def transition_release_plan_issue(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    release_delivery_plans_document: Path,
) -> Mapping[str, str] | None:
    """Reject a same-ID C23 document that changes the run's named facts."""

    try:
        release_plan = load_selected_macos_host_package_release_plan(
            release_delivery_plans_document, evidence_run.release_delivery_plan_id
        )
    except ProductDeliveryReleasePlanError as error:
        return {
            "code": "macos-host-platform-transition-release-plan-unavailable",
            "message": "The explicit C23 document cannot be selected for this C24 run: " + str(error),
        }
    if (
        release_plan.product_version != evidence_run.product_version
        or release_plan.expected_package_file_name != evidence_run.intended_installer_file_name
        or release_plan.macos_installer_package_identifier
        != evidence_run.macos_installer_package_identifier
        or release_plan.macos_installer_signature_policy
        != evidence_run.macos_installer_signature_policy
        or release_plan.host_agent_launchd_service_label
        != evidence_run.host_agent_launchd_service_label
        or release_plan.host_edge_proxy_launchd_service_label
        != evidence_run.host_edge_proxy_launchd_service_label
        or release_plan.host_update_handoff_supervisor_launchd_service_label
        != evidence_run.host_update_handoff_supervisor_launchd_service_label
    ):
        return {
            "code": "macos-host-platform-transition-release-plan-mismatch",
            "message": "The explicit C23 document does not preserve this run's PKG, signature, and launchd identities.",
        }
    return None


def host_platform_transition_os_issue(
    stage: str,
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    transition: host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence,
    package_receipt: MacOSPackageReceiptObservation,
    service_observations: Sequence[MacOSLaunchdServiceRegistrationObservation],
) -> Mapping[str, str] | None:
    """Compare fresh pkgutil/launchctl facts with the C48/C49 transition."""

    if package_receipt.state != "installed":
        return {
            "code": "macos-host-platform-" + stage + "-package-not-installed",
            "message": "pkgutil did not explicitly report the Host Platform package as installed after the transition.",
        }
    if package_receipt.package_identifier != transition.observed_package_identifier:
        return {
            "code": "macos-host-platform-" + stage + "-package-identifier-mismatch",
            "message": "The fresh pkgutil package identifier does not match the C48/C49 transition observation.",
        }
    if package_receipt.product_version != transition.observed_product_version:
        return {
            "code": "macos-host-platform-" + stage + "-package-version-mismatch",
            "message": "The fresh pkgutil product version does not match the C48/C49 transition observation.",
        }
    if any(observation.state != "registered" for observation in service_observations):
        return {
            "code": "macos-host-platform-" + stage + "-service-registration-not-observed",
            "message": "A required launchd service was not registered after the Host Platform transition.",
        }
    if stage == UPDATE_STAGE and package_receipt.product_version != evidence_run.product_version:
        return {
            "code": "macos-host-platform-update-target-version-mismatch",
            "message": "The successful update did not leave the C23 target product version installed.",
        }
    return None


def validate_macos_preserving_removal_inputs(
    host_installation_manager_path: Path,
    installed_manifest_path: Path,
    installation_journal_path: Path,
    installation_receipt_path: Path,
    removal_journal_path: Path,
    removal_receipt_path: Path,
    removal_request_id: str,
    expected_installation_id: str,
    expected_release_id: str,
) -> None:
    """Reject missing C54 inputs before the manager is allowed to mutate Host state."""

    for label, path in (
        ("Host Installation Manager", host_installation_manager_path),
        ("installed C48 manifest", installed_manifest_path),
        ("C50 installation journal", installation_journal_path),
        ("C50 installation receipt", installation_receipt_path),
    ):
        if not path.is_absolute() or path.is_symlink() or not path.is_file():
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS C54 " + label + " must be one absolute regular non-symlink file"
            )
    if not os.access(host_installation_manager_path, os.X_OK):
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS C54 Host Installation Manager is not executable"
        )
    for label, path in (
        ("C54 removal journal", removal_journal_path),
        ("C54 removal receipt", removal_receipt_path),
    ):
        if not path.is_absolute() or not path.parent.is_dir():
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS " + label + " path must be absolute with an existing parent directory"
            )
        if path.exists() or path.is_symlink():
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS " + label + " must not already exist for a new C54 transition"
            )
    for label, value in (
        ("C54 removal request ID", removal_request_id),
        ("C54 expected installation ID", expected_installation_id),
        ("C54 expected release ID", expected_release_id),
    ):
        if not isinstance(value, str) or not value:
            raise MacOSCleanHostReleaseEvidenceRunError(
                "macOS " + label + " is required"
            )


def observe_completed_macos_preservation_removal_receipt(
    receipt_path: Path,
    expected_installation_id: str,
    expected_release_id: str,
) -> tuple[Mapping[str, Any] | None, str | None, Mapping[str, str] | None]:
    """Read only a completed C54 preservation receipt; absence stays explicit."""

    if not receipt_path.is_absolute() or receipt_path.is_symlink() or not receipt_path.is_file():
        return None, None, {
            "code": "macos-removal-receipt-unavailable",
            "message": "The C54 removal receipt must be one absolute regular non-symlink file.",
        }
    try:
        payload = receipt_path.read_bytes()
        receipt = json.loads(payload)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return None, None, {
            "code": "macos-removal-receipt-unreadable",
            "message": "The C54 removal receipt could not be decoded: " + str(error),
        }
    if not isinstance(receipt, dict):
        return None, None, {
            "code": "macos-removal-receipt-invalid",
            "message": "The C54 removal receipt must contain one JSON object.",
        }
    expected_facts = {
        "schemaVersion": "v1",
        "documentKind": "host-product-removal-receipt",
        "installationId": expected_installation_id,
        "releaseId": expected_release_id,
        "dataDisposition": "preserve-mutable-data",
        "state": "completed",
        "packageReceiptRemoval": "removed-by-host-installation-manager",
    }
    if any(receipt.get(key) != value for key, value in expected_facts.items()):
        return None, None, {
            "code": "macos-removal-receipt-does-not-prove-preserving-completion",
            "message": "The C54 receipt does not match the declared completed macOS preservation removal.",
        }
    for field in ("id", "requestId", "observedAt"):
        if not isinstance(receipt.get(field), str) or not receipt[field]:
            return None, None, {
                "code": "macos-removal-receipt-invalid",
                "message": "The C54 receipt is missing required field " + field + ".",
            }
    retained = receipt.get("retainedMutableStoreIds")
    if retained is not None and (
        not isinstance(retained, list)
        or any(not isinstance(item, str) or not item for item in retained)
        or len(set(retained)) != len(retained)
    ):
        return None, None, {
            "code": "macos-removal-receipt-invalid",
            "message": "The C54 receipt retained mutable store IDs are invalid.",
        }
    return receipt, hashlib.sha256(payload).hexdigest(), None


def macos_preserving_removal_issue(
    removal_command: MacOSCleanHostReleaseEvidenceCommandObservation,
    removal_receipt_issue: Mapping[str, str] | None,
    package_receipt: MacOSPackageReceiptObservation,
    service_observations: Sequence[MacOSLaunchdServiceRegistrationObservation],
) -> Mapping[str, str] | None:
    if removal_command.returncode != 0:
        return {
            "code": "macos-uninstall-command-failed",
            "message": "Host Installation Manager returned a non-zero result for the explicit C54 removal.",
        }
    if removal_receipt_issue is not None:
        return removal_receipt_issue
    if package_receipt.state != "absent":
        return {
            "code": "macos-uninstall-package-receipt-not-absent",
            "message": "pkgutil did not explicitly report the removed package receipt as absent.",
        }
    if any(observation.state != "absent" for observation in service_observations):
        return {
            "code": "macos-uninstall-service-registration-remains",
            "message": "A C23-required launchd service remained registered after C54 removal.",
        }
    return None


def macos_reinstall_after_preserving_removal_issue(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    installer_command: MacOSCleanHostReleaseEvidenceCommandObservation,
    package_receipt: MacOSPackageReceiptObservation,
    service_observations: Sequence[MacOSLaunchdServiceRegistrationObservation],
) -> Mapping[str, str] | None:
    if installer_command.returncode != 0:
        return {
            "code": "macos-reinstall-command-failed",
            "message": "macOS installer returned a non-zero result for explicit reinstallation.",
        }
    return installed_receipt_or_service_registration_issue(
        evidence_run, package_receipt, service_observations
    )


def observe_installed_guest_runtime_evidence(
    evidence_run: MacOSCleanHostReleaseEvidenceRun,
    contract_root: Path,
    first_boot_evidence_path: Path,
    direct_upload_evidence_path: Path,
    post_reboot_evidence_path: Path,
) -> tuple[Mapping[str, Any], Mapping[str, str] | None]:
    """Validate and bind the three immutable C78 owner documents.

    C24 does not rediscover Guest state here. It only validates caller-selected
    C78 documents, their release/runner identity, and their explicit evidence
    chain before embedding the exact documents and byte identities in one C24
    stage evidence record.
    """

    source_paths = (
        ("first-boot-checkpoint", first_boot_evidence_path),
        ("direct-upload-lineage", direct_upload_evidence_path),
        ("post-reboot-identity", post_reboot_evidence_path),
    )
    details: dict[str, Any] = {
        "guestInstalledRuntimeEvidenceSources": [
            {"stage": stage, "path": str(path)} for stage, path in source_paths
        ]
    }
    if (
        not contract_root.is_absolute()
        or not contract_root.is_dir()
        or not (
            contract_root / "contracts" / "catalog" / "v1.json"
        ).is_file()
    ):
        return details, {
            "code": "installed-guest-runtime-contract-root-invalid",
            "message": "The selected C78 contract root is not an explicit runtime-platform contract repository.",
        }
    if len({path for _, path in source_paths}) != len(source_paths):
        return details, {
            "code": "installed-guest-runtime-evidence-path-duplicated",
            "message": "Each C78 stage must be supplied by a distinct evidence file.",
        }

    try:
        repository = ContractRepository(contract_root)
        repository.load()
    except ContractToolError as error:
        return details, {
            "code": "installed-guest-runtime-contract-unavailable",
            "message": "The selected C78 contract repository could not be loaded: "
            + str(error),
        }

    documents: dict[str, Mapping[str, Any]] = {}
    source_identities: list[Mapping[str, str]] = []
    for expected_stage, path in source_paths:
        if not path.is_absolute() or path.is_symlink() or not path.is_file():
            return details, {
                "code": "installed-guest-runtime-evidence-source-invalid",
                "message": "C78 evidence must be an absolute regular non-symlink file for stage "
                + expected_stage
                + ".",
            }
        try:
            payload = path.read_bytes()
        except OSError as error:
            return details, {
                "code": "installed-guest-runtime-evidence-read-failed",
                "message": "C78 evidence could not be read for stage "
                + expected_stage
                + ": "
                + str(error),
            }
        try:
            document = json.loads(payload)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            return details, {
                "code": "installed-guest-runtime-evidence-decode-failed",
                "message": "C78 evidence is not valid JSON for stage "
                + expected_stage
                + ": "
                + str(error),
            }
        if not isinstance(document, dict):
            return details, {
                "code": "installed-guest-runtime-evidence-contract-invalid",
                "message": "C78 evidence must be an object for stage "
                + expected_stage
                + ".",
            }
        findings = repository.validate_instance(
            "guest-installed-runtime-evidence.schema.json", document
        )
        if findings:
            return details, {
                "code": "installed-guest-runtime-evidence-contract-invalid",
                "message": "C78 evidence failed its published contract for stage "
                + expected_stage
                + ": "
                + "; ".join(finding.render() for finding in findings),
            }
        if document.get("stage") != expected_stage:
            return details, {
                "code": "installed-guest-runtime-evidence-stage-mismatch",
                "message": "The selected C78 evidence stage does not match "
                + expected_stage
                + ".",
            }
        if document.get("status") != "verified":
            return details, {
                "code": "installed-guest-runtime-evidence-not-verified",
                "message": "C24 cannot attach non-verified C78 evidence for stage "
                + expected_stage
                + ".",
            }
        if (
            document.get("releaseDeliveryPlanId")
            != evidence_run.release_delivery_plan_id
        ):
            return details, {
                "code": "installed-guest-runtime-release-plan-mismatch",
                "message": "C78 evidence does not name the C24 release delivery plan for stage "
                + expected_stage
                + ".",
            }
        runner = document.get("runner")
        if (
            not isinstance(runner, dict)
            or runner.get("id") != evidence_run.runner_id
        ):
            return details, {
                "code": "installed-guest-runtime-runner-mismatch",
                "message": "C78 evidence does not name the C24 clean-Host runner for stage "
                + expected_stage
                + ".",
            }
        documents[expected_stage] = document
        source_identities.append(
            {
                "stage": expected_stage,
                "uri": path.as_uri(),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }
        )

    first_boot = documents["first-boot-checkpoint"]
    direct_upload = documents["direct-upload-lineage"]
    post_reboot = documents["post-reboot-identity"]
    if (
        direct_upload.get("checkpointEvidenceId") != first_boot.get("evidenceId")
        or post_reboot.get("checkpointEvidenceId") != first_boot.get("evidenceId")
        or post_reboot.get("directUploadEvidenceId")
        != direct_upload.get("evidenceId")
    ):
        return details, {
            "code": "installed-guest-runtime-evidence-chain-mismatch",
            "message": "C78 evidence references do not form one first-boot, direct-upload, and post-reboot chain.",
        }
    if (
        post_reboot.get("hostBootSessionIdentifier")
        == first_boot.get("hostBootSessionIdentifier")
    ):
        return details, {
            "code": "installed-guest-runtime-reboot-not-observed",
            "message": "C78 first-boot and post-reboot evidence name the same Host boot session.",
        }
    first_identity = first_boot["identity"]
    post_identity = post_reboot["identity"]
    for owner in ("sqlite", "postgresql", "bootstrap"):
        if first_identity.get(owner) != post_identity.get(owner):
            return details, {
                "code": "installed-guest-runtime-owner-identity-mismatch",
                "message": "C78 Guest " + owner + " owner identity changed after reboot.",
            }

    return {
        "guestInstalledRuntimeEvidenceSources": source_identities,
        "guestInstalledRuntimeEvidence": [
            documents[stage] for stage, _ in source_paths
        ],
    }, None


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
        "macOSInstallerSignaturePolicy": evidence_run.macos_installer_signature_policy,
        "hostAgentLaunchdServiceLabel": (
            evidence_run.host_agent_launchd_service_label
        ),
        "hostEdgeProxyLaunchdServiceLabel": (
            evidence_run.host_edge_proxy_launchd_service_label
        ),
        "hostUpdateHandoffSupervisorLaunchdServiceLabel": (
            evidence_run.host_update_handoff_supervisor_launchd_service_label
        ),
        "boundInstallerArtifactSHA256": evidence_run.bound_installer_artifact_sha256,
    }


def command_document(
    command: MacOSCleanHostReleaseEvidenceCommandObservation,
) -> Mapping[str, Any]:
    return macos_host_installation_observation.command_document(command)


def installer_artifact_release_identity_document(
    installer_artifact_release_identity: MacOSInstallerArtifactReleaseIdentityObservation,
) -> Mapping[str, Any]:
    return macos_host_installation_observation.installer_artifact_identity_document(
        installer_artifact_release_identity
    )


def package_receipt_document(
    package_receipt: MacOSPackageReceiptObservation,
) -> Mapping[str, Any]:
    return macos_host_installation_observation.package_receipt_document(package_receipt)


def launchd_service_registration_document(
    service_observation: MacOSLaunchdServiceRegistrationObservation,
) -> Mapping[str, Any]:
    return macos_host_installation_observation.launchd_service_registration_document(
        service_observation
    )


def boot_session_document(
    boot_session: MacOSHostBootSessionObservation,
) -> Mapping[str, Any]:
    return macos_host_installation_observation.boot_session_document(boot_session)


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
    try:
        return macos_host_installation_observation.parse_macos_installed_package_receipt_output(
            output
        )
    except macos_host_installation_observation.MacOSHostInstallationObservationError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(
            str(error)
        ) from error


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


def write_new_c24_proof_fragment(
    output_proof_fragment_path: Path,
    stage_record: MacOSCleanHostReleaseEvidenceStageRecord,
) -> tuple[Path, str]:
    """Publish one runner-owned C24 fragment without changing its journal.

    The runner owns the proof bytes it previously recorded in its SQLite
    journal.  The Release process owns later C74 review and proof-set
    attachment.  Requiring one new caller-selected path keeps these two facts
    separate and prevents a retry from replacing a previously reviewed file.
    """

    if stage_record.c24_proof is None:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS clean-Host release evidence stage has no C24 proof: "
            + stage_record.stage
        )
    if not output_proof_fragment_path.is_absolute():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS C24 proof fragment output path must be absolute"
        )
    if not output_proof_fragment_path.parent.is_dir():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS C24 proof fragment output parent directory is missing: "
            + str(output_proof_fragment_path.parent)
        )
    if output_proof_fragment_path.exists() or output_proof_fragment_path.is_symlink():
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS C24 proof fragment output already exists: "
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
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS C24 proof fragment output already exists: "
            + str(output_proof_fragment_path)
        ) from error
    except OSError as error:
        raise MacOSCleanHostReleaseEvidenceRunError(
            "macOS C24 proof fragment write failed: " + str(error)
        ) from error
    return output_proof_fragment_path, sha256_file(output_proof_fragment_path)


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
        "write-stage-proof-fragment",
    ):
        command = subcommands.add_parser(command_name)
        command.add_argument("--journal-path", required=True)
        if command_name in {"print-stage-proof", "write-stage-proof-fragment"}:
            command.add_argument(
                "--stage",
                required=True,
                choices=C24_PROOF_STAGES,
            )
        if command_name == "write-stage-proof-fragment":
            command.add_argument("--output-proof-fragment", required=True, type=Path)

    installed_guest_runtime = subcommands.add_parser(
        "record-installed-guest-runtime",
        help="attach one complete verified C78 evidence chain after reboot",
    )
    installed_guest_runtime.add_argument("--journal-path", required=True)
    installed_guest_runtime.add_argument("--contract-root", required=True, type=Path)
    installed_guest_runtime.add_argument(
        "--first-boot-evidence", required=True, type=Path
    )
    installed_guest_runtime.add_argument(
        "--direct-upload-evidence", required=True, type=Path
    )
    installed_guest_runtime.add_argument(
        "--post-reboot-evidence", required=True, type=Path
    )

    for command_name in ("record-host-platform-update", "record-host-platform-rollback"):
        command = subcommands.add_parser(command_name)
        command.add_argument("--journal-path", required=True)
        command.add_argument("--release-delivery-plans-document", required=True)
        command.add_argument("--host-update-journal", required=True)
        command.add_argument("--host-platform-effect-receipt", required=True)
        command.add_argument("--host-installation-manifest", required=True)
        command.add_argument("--host-installation-footprint", required=True)

    clean_install = subcommands.add_parser("execute-clean-install")
    clean_install.add_argument("--journal-path", required=True)
    clean_install.add_argument(
        "--authorize-clean-install",
        action="store_true",
        help="explicitly authorize the irreversible macOS installer effect",
    )

    uninstall_reinstall = subcommands.add_parser(
        "execute-uninstall-reinstall-preserving-data",
        help="run one explicit C54 preservation removal followed by a fresh PKG installation",
    )
    uninstall_reinstall.add_argument("--journal-path", required=True)
    uninstall_reinstall.add_argument("--host-installation-manager", required=True)
    uninstall_reinstall.add_argument("--installed-manifest", required=True)
    uninstall_reinstall.add_argument("--installation-journal", required=True)
    uninstall_reinstall.add_argument("--installation-receipt", required=True)
    uninstall_reinstall.add_argument("--removal-journal", required=True)
    uninstall_reinstall.add_argument("--removal-receipt", required=True)
    uninstall_reinstall.add_argument("--removal-request-id", required=True)
    uninstall_reinstall.add_argument("--expected-installation-id", required=True)
    uninstall_reinstall.add_argument("--expected-release-id", required=True)
    uninstall_reinstall.add_argument(
        "--authorize-uninstall-reinstall",
        action="store_true",
        help="explicitly authorize the irreversible C54 removal and fresh installer effects",
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
        elif parsed.command == "record-installed-guest-runtime":
            stage_record = evidence_runner.record_installed_guest_runtime(
                parsed.contract_root,
                parsed.first_boot_evidence,
                parsed.direct_upload_evidence,
                parsed.post_reboot_evidence,
            )
        elif parsed.command in {"record-host-platform-update", "record-host-platform-rollback"}:
            record_transition = (
                evidence_runner.record_host_platform_update
                if parsed.command == "record-host-platform-update"
                else evidence_runner.record_host_platform_rollback
            )
            stage_record = record_transition(
                Path(parsed.release_delivery_plans_document),
                Path(parsed.host_update_journal),
                Path(parsed.host_platform_effect_receipt),
                Path(parsed.host_installation_manifest),
                Path(parsed.host_installation_footprint),
            )
        elif parsed.command == "execute-uninstall-reinstall-preserving-data":
            if not parsed.authorize_uninstall_reinstall:
                raise MacOSCleanHostReleaseEvidenceRunError(
                    "macOS clean-Host uninstall/reinstall requires --authorize-uninstall-reinstall"
                )
            stage_record = evidence_runner.execute_uninstall_reinstall_preserving_data(
                Path(parsed.host_installation_manager),
                Path(parsed.installed_manifest),
                Path(parsed.installation_journal),
                Path(parsed.installation_receipt),
                Path(parsed.removal_journal),
                Path(parsed.removal_receipt),
                parsed.removal_request_id,
                parsed.expected_installation_id,
                parsed.expected_release_id,
            )
        elif parsed.command in {"print-stage-proof", "write-stage-proof-fragment"}:
            stage_record = journal.load_stage_record(parsed.stage)
            if stage_record is None or stage_record.c24_proof is None:
                raise MacOSCleanHostReleaseEvidenceRunError(
                    "macOS clean-Host release evidence stage has no C24 proof: "
                    + parsed.stage
                )
            if parsed.command == "print-stage-proof":
                print(canonical_json(stage_record.c24_proof))
                return 0
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
