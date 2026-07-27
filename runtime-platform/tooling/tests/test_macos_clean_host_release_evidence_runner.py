"""Release-process tests for macOS clean-Host C24 evidence collection."""

from __future__ import annotations

from contextlib import closing
import json
from dataclasses import replace
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest import mock

from tooling import macos_clean_host_release_evidence_runner as evidence_runner
from tooling.contracts import ContractRepository


class MacOSCleanHostReleaseEvidenceRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.evidence_directory = self.root / "evidence"
        self.evidence_directory.mkdir()
        self.artifact = self.root / "VitalServerRuntimePlatform-0.2.0-dev.pkg"
        self.artifact.write_bytes(b"signed macOS release package bytes")
        self.journal_path = self.root / "macos-clean-host-evidence.sqlite"
        self.release_delivery_plans_document = (
            Path(__file__).resolve().parents[2]
            / "product"
            / "delivery"
            / "release-delivery-plans.v1.json"
        )
        pkgutil_executable = self.write_command_contract_fixture("pkgutil")
        installer_executable = self.write_command_contract_fixture("installer")
        launchctl_executable = self.write_command_contract_fixture("launchctl")
        sysctl_executable = self.write_command_contract_fixture("sysctl")
        self.command_contract = (
            evidence_runner.MacOSCleanHostReleaseEvidenceCommandContract(
                pkgutil_executable=pkgutil_executable,
                installer_executable=installer_executable,
                launchctl_executable=launchctl_executable,
                sysctl_executable=sysctl_executable,
            )
        )
        self.package_receipt_installed = False
        self.launchd_services_registered = False
        self.installer_invocation_count = 0
        self.boot_session_identifiers = iter(("boot-session-before", "boot-session-after"))
        self.host_installation_manager = self.root / "host-installation-manager"
        self.host_installation_manager.write_text("fixture", encoding="utf-8")
        self.host_installation_manager.chmod(0o755)
        self.installed_manifest = self.root / "installation-manifest.json"
        self.installed_manifest.write_text("{}", encoding="utf-8")
        self.installation_journal = self.root / "current-installation.json"
        self.installation_journal.write_text("{}", encoding="utf-8")
        self.installation_receipt = self.root / "latest-installation.json"
        self.installation_receipt.write_text("{}", encoding="utf-8")
        self.removal_journal = self.root / "current-removal.json"
        self.removal_receipt = self.root / "latest-removal.json"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_command_contract_fixture(self, executable_name: str) -> Path:
        executable_path = self.root / "commands" / executable_name
        executable_path.parent.mkdir(exist_ok=True)
        executable_path.write_text("#!/bin/sh\nexit 64\n", encoding="utf-8")
        executable_path.chmod(0o755)
        return executable_path

    def create_evidence_run(self) -> evidence_runner.MacOSCleanHostReleaseEvidenceRun:
        return evidence_runner.create_macos_clean_host_release_evidence_run(
            journal_path=self.journal_path,
            evidence_directory=self.evidence_directory,
            installer_artifact_path=self.artifact,
            release_delivery_plans_document=self.release_delivery_plans_document,
            release_delivery_plan_id="macos-runtime-platform-release",
            run_id="macos-clean-host-evidence-01",
            runner_id="macos-clean-host-runner-01",
            command_contract=self.command_contract,
        )

    def command_result(
        self, executable: Path, arguments: list[str]
    ) -> evidence_runner.MacOSCleanHostReleaseEvidenceCommandObservation:
        if executable == self.command_contract.pkgutil_executable:
            if arguments[0] == "--check-signature":
                return self.result(
                    executable,
                    arguments,
                    1,
                    "Package \"VitalServerRuntimePlatform\":\n   Status: no signature\n",
                )
            if arguments[0] == "--pkg-info":
                if self.package_receipt_installed:
                    return self.result(
                        executable,
                        arguments,
                        0,
                        "package-id: com.tirosh.vitalserver.runtime-platform\nversion: 0.2.0-dev\n",
                    )
                return self.result(
                    executable,
                    arguments,
                    1,
                    "",
                    "No receipt for 'com.tirosh.vitalserver.runtime-platform' found at '/'.\n",
                )
        if executable == self.command_contract.installer_executable:
            self.installer_invocation_count += 1
            self.package_receipt_installed = True
            if self.installer_invocation_count > 1:
                self.launchd_services_registered = True
            return self.result(executable, arguments, 0, "installer: completed\n")
        if executable == self.host_installation_manager:
            self.package_receipt_installed = False
            self.launchd_services_registered = False
            self.removal_journal.write_text("{}", encoding="utf-8")
            self.removal_receipt.write_text(
                json.dumps(
                    {
                        "schemaVersion": "v1",
                        "documentKind": "host-product-removal-receipt",
                        "id": "remove-020-receipt",
                        "requestId": "remove-020",
                        "installationId": "vitalserver-runtime-platform-macos-reference",
                        "releaseId": "runtime-platform-020",
                        "dataDisposition": "preserve-mutable-data",
                        "state": "completed",
                        "packageReceiptRemoval": "removed-by-host-installation-manager",
                        "retainedMutableStoreIds": ["virtual-machine-runtime"],
                        "observedAt": "2026-07-20T00:03:00Z",
                    }
                ),
                encoding="utf-8",
            )
            return self.result(executable, arguments, 0, "C54 completed\n")
        if executable == self.command_contract.launchctl_executable:
            if self.launchd_services_registered:
                return self.result(executable, arguments, 0, "service = registered\n")
            service_label = arguments[1].removeprefix("system/")
            return self.result(
                executable,
                arguments,
                113,
                "",
                "Could not find service \"" + service_label + "\" in domain for system\n",
            )
        if executable == self.command_contract.sysctl_executable:
            return self.result(executable, arguments, 0, next(self.boot_session_identifiers) + "\n")
        self.fail("unexpected executable: " + str(executable))

    @staticmethod
    def result(
        executable: Path,
        arguments: list[str],
        returncode: int,
        stdout: str,
        stderr: str = "",
    ) -> evidence_runner.MacOSCleanHostReleaseEvidenceCommandObservation:
        return evidence_runner.MacOSCleanHostReleaseEvidenceCommandObservation(
            executable=executable,
            arguments=tuple(arguments),
            returncode=returncode,
            stdout=stdout,
            stderr=stderr,
        )

    def available_installer_artifact_package_metadata_observation(
        self,
    ) -> evidence_runner.MacOSInstallerArtifactReleaseIdentityObservation:
        return evidence_runner.MacOSInstallerArtifactReleaseIdentityObservation(
            state="available",
            package_identifier="com.tirosh.vitalserver.runtime-platform",
            product_version="0.2.0-dev",
            package_expansion_command=self.result(
                self.command_contract.pkgutil_executable,
                ["--expand", str(self.artifact), "/temporary/expanded-package"],
                0,
                "",
            ),
        )

    def write_verified_c78_evidence_chain(self) -> tuple[Path, Path, Path]:
        contract_root = Path(__file__).resolve().parents[2]
        first_boot = json.loads(
            (
                contract_root
                / "contracts/examples/v1/valid/guest-installed-runtime-evidence-first-boot.json"
            ).read_text(encoding="utf-8")
        )
        first_boot["evidenceId"] = "c78-run-01-first-boot-checkpoint"
        first_boot["runner"]["id"] = "macos-clean-host-runner-01"

        assignment_receipt = json.loads(
            (
                contract_root
                / "contracts/examples/v1/valid/recorder-assignment-evidence-receipt.json"
            ).read_text(encoding="utf-8")
        )
        artifact = json.loads(
            (
                contract_root
                / "contracts/examples/v1/valid/archive-artifact-detail.json"
            ).read_text(encoding="utf-8")
        )
        direct_upload = {
            "schemaVersion": "v1",
            "evidenceId": "c78-run-01-direct-upload-lineage",
            "releaseDeliveryPlanId": "macos-runtime-platform-release",
            "stage": "direct-upload-lineage",
            "status": "verified",
            "recordedAt": "2026-07-24T23:31:00Z",
            "runner": {
                "kind": "guest-installed-runtime",
                "id": "macos-clean-host-runner-01",
            },
            "checkpointEvidenceId": first_boot["evidenceId"],
            "edgeEndpoint": "http://edge/",
            "sourceVitalFile": {
                "fileName": "OR-01-20260724.vital",
                "byteSize": 20480,
                "sha256": "a" * 64,
            },
            "uploadId": "upload-01",
            "recorderId": "recorder-1",
            "reportedBedName": "OR-01",
            "declaredRecorderCode": "VR-01",
            "assignmentReceipt": assignment_receipt,
            "artifact": artifact,
        }
        post_reboot = json.loads(json.dumps(first_boot))
        post_reboot.update(
            {
                "evidenceId": "c78-run-01-post-reboot-identity",
                "stage": "post-reboot-identity",
                "recordedAt": "2026-07-24T23:40:00Z",
                "checkpointEvidenceId": first_boot["evidenceId"],
                "directUploadEvidenceId": direct_upload["evidenceId"],
                "hostBootSessionIdentifier": "host-boot-session-after",
                "readinessObservedAt": "2026-07-24T23:39:59Z",
            }
        )
        post_reboot["identity"]["observedAt"] = "2026-07-24T23:39:59Z"

        paths = (
            self.root / "c78-first-boot.json",
            self.root / "c78-direct-upload.json",
            self.root / "c78-post-reboot.json",
        )
        documents = (first_boot, direct_upload, post_reboot)
        self.assertEqual(len(paths), len(documents))
        for path, document in zip(paths, documents):
            path.write_text(json.dumps(document), encoding="utf-8")
        return paths

    def test_collects_explicit_clean_host_install_service_and_reboot_evidence(self) -> None:
        evidence_run = self.create_evidence_run()
        self.assertEqual(
            "com.tirosh.vitalserver.runtime-platform",
            evidence_run.macos_installer_package_identifier,
        )
        self.assertEqual(
            "com.tirosh.vitalserver.host-update-handoff-supervisor",
            evidence_run.host_update_handoff_supervisor_launchd_service_label,
        )
        self.assertEqual("unsigned", evidence_run.macos_installer_signature_policy)

        journal = evidence_runner.MacOSCleanHostReleaseEvidenceJournal(
            self.journal_path
        )
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(journal)
        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0):
            artifact_integrity = runner.record_artifact_integrity()
            clean_host_preflight = runner.record_clean_host_preflight()
            clean_install = runner.execute_clean_install()
            self.launchd_services_registered = True
            service_registration = runner.record_service_registration()
            reboot_checkpoint = runner.record_reboot_checkpoint()
            reboot = runner.record_reboot()
            first_boot, direct_upload, post_reboot = (
                self.write_verified_c78_evidence_chain()
            )
            installed_guest_runtime = runner.record_installed_guest_runtime(
                Path(__file__).resolve().parents[2],
                first_boot,
                direct_upload,
                post_reboot,
            )

        self.assertEqual("verified", artifact_integrity.status)
        self.assertEqual("verified", clean_host_preflight.status)
        self.assertEqual("verified", clean_install.status)
        self.assertEqual("verified", service_registration.status)
        self.assertEqual("verified", reboot_checkpoint.status)
        self.assertEqual("verified", reboot.status)
        self.assertEqual("verified", installed_guest_runtime.status)
        self.assertTrue(artifact_integrity.evidence_path.is_file())
        self.assertEqual(
            "artifact-integrity", artifact_integrity.c24_proof["stage"]
        )
        self.assertEqual(
            "com.tirosh.vitalserver.runtime-platform",
            clean_install.c24_proof["observedMacOSInstallerReceipt"][
                "packageIdentifier"
            ],
        )
        self.assertEqual(
            [
                "host-agent",
                "host-edge-proxy",
                "host-update-handoff-supervisor",
            ],
            [
                registration["role"]
                for registration in service_registration.c24_proof[
                    "observedHostServiceRegistrations"
                ]
            ],
        )
        self.assertEqual("reboot", reboot.c24_proof["stage"])
        self.assertEqual(
            "installed-guest-runtime",
            installed_guest_runtime.c24_proof["stage"],
        )
        self.assertEqual(
            [
                "first-boot-checkpoint",
                "direct-upload-lineage",
                "post-reboot-identity",
            ],
            [
                item["stage"]
                for item in json.loads(
                    installed_guest_runtime.evidence_path.read_text(encoding="utf-8")
                )["details"]["guestInstalledRuntimeEvidence"]
            ],
        )
        contract_repository = ContractRepository(
            Path(__file__).resolve().parents[2]
        )
        contract_repository.load()
        for stage_record in (
            artifact_integrity,
            clean_install,
            service_registration,
            reboot,
            installed_guest_runtime,
        ):
            self.assertEqual(
                [],
                contract_repository.validate_instance(
                    "release-delivery-proof.schema.json",
                    {"schemaVersion": "v1", "proofs": [stage_record.c24_proof]},
                ),
            )
        proof_fragment_path = self.root / "artifact-integrity-proof.json"
        published_path, published_sha256 = evidence_runner.write_new_c24_proof_fragment(
            proof_fragment_path, artifact_integrity
        )
        self.assertEqual(proof_fragment_path, published_path)
        self.assertEqual(published_sha256, evidence_runner.sha256_file(proof_fragment_path))
        self.assertEqual(
            {"schemaVersion": "v1", "proofs": [artifact_integrity.c24_proof]},
            json.loads(proof_fragment_path.read_text(encoding="utf-8")),
        )
        with self.assertRaisesRegex(
            evidence_runner.MacOSCleanHostReleaseEvidenceRunError,
            "output already exists",
        ):
            evidence_runner.write_new_c24_proof_fragment(
                proof_fragment_path, artifact_integrity
            )
        self.assertNotEqual(
            json.loads(
                reboot_checkpoint.evidence_path.read_text(encoding="utf-8")
            )["details"]["bootSessionObservation"]["bootSessionIdentifier"],
            json.loads(reboot.evidence_path.read_text(encoding="utf-8"))["details"][
                "postRebootBootSessionObservation"
            ]["bootSessionIdentifier"],
        )

    def test_records_failed_installed_guest_runtime_when_c78_chain_is_mismatched(
        self,
    ) -> None:
        self.create_evidence_run()
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0):
            runner.record_artifact_integrity()
            runner.record_clean_host_preflight()
            runner.execute_clean_install()
            self.launchd_services_registered = True
            runner.record_service_registration()
            runner.record_reboot_checkpoint()
            runner.record_reboot()

        first_boot, direct_upload, post_reboot = (
            self.write_verified_c78_evidence_chain()
        )
        direct_document = json.loads(direct_upload.read_text(encoding="utf-8"))
        direct_document["checkpointEvidenceId"] = "different-first-boot-evidence"
        direct_upload.write_text(json.dumps(direct_document), encoding="utf-8")

        installed_guest_runtime = runner.record_installed_guest_runtime(
            Path(__file__).resolve().parents[2],
            first_boot,
            direct_upload,
            post_reboot,
        )

        self.assertEqual("failed", installed_guest_runtime.status)
        self.assertEqual(
            "installed-guest-runtime-evidence-chain-mismatch",
            installed_guest_runtime.c24_proof["issue"]["code"],
        )

    def test_missing_required_update_handoff_supervisor_registration_fails_service_evidence(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        def command_with_missing_update_handoff_supervisor(
            executable: Path,
            arguments: list[str],
        ) -> evidence_runner.MacOSCleanHostReleaseEvidenceCommandObservation:
            if (
                executable == self.command_contract.launchctl_executable
                and arguments[1]
                == "system/com.tirosh.vitalserver.host-update-handoff-supervisor"
                and self.launchd_services_registered
            ):
                return self.result(
                    executable,
                    arguments,
                    113,
                    "",
                    "Could not find service \"com.tirosh.vitalserver.host-update-handoff-supervisor\" in domain for system\n",
                )
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=command_with_missing_update_handoff_supervisor,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.launchd_services_registered = True
            registration = runner.record_service_registration()

        self.assertEqual("failed", registration.status)
        self.assertEqual(
            "macos-launchd-service-registration-not-observed",
            registration.c24_proof["issue"]["code"],
        )

    def test_records_host_platform_update_only_after_fresh_pkgutil_and_launchctl_observations(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        transition = evidence_runner.host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence(
            stage="update",
            release_delivery_plan_id="macos-runtime-platform-release",
            platform="macos",
            provider_kind="macos-virtualization",
            target_product_version="0.2.0-dev",
            update_id="update-020",
            request_id="request-020",
            bootstrap_envelope_id="bootstrap-020",
            update_specification_sha256="b" * 64,
            host_platform_artifact_sha256="a" * 64,
            inputs=(),
            rollback_evidence=None,
            observed_installation_id="vitalserver-runtime-platform-macos",
            observed_release_id="runtime-platform-020",
            observed_product_version="0.2.0-dev",
            observed_package_identifier="com.tirosh.vitalserver.runtime-platform",
            observed_at="2026-07-20T00:02:00Z",
        )
        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0), mock.patch.object(
            evidence_runner.host_platform_release_transition_evidence,
            "inspect_host_platform_update_transition",
            return_value=transition,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.launchd_services_registered = True
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.assertEqual("verified", runner.record_reboot().status)
            update = runner.record_host_platform_update(
                self.release_delivery_plans_document,
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
            )

        self.assertEqual("verified", update.status)
        self.assertEqual("update", update.c24_proof["stage"])
        self.assertEqual(
            "0.2.0-dev",
            json.loads(update.evidence_path.read_text(encoding="utf-8"))["details"]
            ["hostPlatformReleaseTransition"]["observedHostInstallation"]["productVersion"],
        )

    def test_pre_update_handoff_evidence_journal_cannot_be_resumed(self) -> None:
        with closing(sqlite3.connect(self.journal_path)) as connection:
            with connection:
                connection.execute(
                    "CREATE TABLE evidence_run (run_id TEXT NOT NULL)"
                )

        with self.assertRaisesRegex(
            evidence_runner.MacOSCleanHostReleaseEvidenceRunError,
            "required C23 service/signature-policy fact",
        ):
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(
                self.journal_path
            ).load_evidence_run()

    def test_transition_rejects_c23_document_that_changes_the_bound_launchd_identity(self) -> None:
        evidence_run = self.create_evidence_run()
        plans = json.loads(self.release_delivery_plans_document.read_text(encoding="utf-8"))
        selected = next(plan for plan in plans["plans"] if plan["id"] == "macos-runtime-platform-release")
        selected["requiredHostServiceRegistrations"][0]["name"] = "com.tirosh.other-host-agent"
        changed_document = (self.root / "changed-release-delivery-plans.json").resolve()
        changed_document.write_text(json.dumps(plans), encoding="utf-8")

        issue = evidence_runner.transition_release_plan_issue(
            evidence_run, changed_document
        )

        self.assertEqual(
            "macos-host-platform-transition-release-plan-mismatch", issue["code"]
        )

    def test_preflight_does_not_treat_unknown_launchctl_failure_as_absence(self) -> None:
        self.create_evidence_run()
        journal = evidence_runner.MacOSCleanHostReleaseEvidenceJournal(
            self.journal_path
        )
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(journal)

        def command_with_unknown_launchctl_failure(
            executable: Path, arguments: list[str]
        ) -> evidence_runner.MacOSCleanHostReleaseEvidenceCommandObservation:
            if executable == self.command_contract.launchctl_executable:
                return self.result(
                    executable,
                    arguments,
                    1,
                    "",
                    "launchctl transport temporarily unavailable\n",
                )
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=command_with_unknown_launchctl_failure,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ):
            artifact_integrity = runner.record_artifact_integrity()
            preflight = runner.record_clean_host_preflight()

        self.assertEqual("verified", artifact_integrity.status)
        self.assertEqual("failed", preflight.status)
        self.assertEqual(
            "macos-clean-host-service-observation-unavailable",
            json.loads(preflight.evidence_path.read_text(encoding="utf-8"))["issue"][
                "code"
            ],
        )
        with self.assertRaisesRegex(
            evidence_runner.MacOSCleanHostReleaseEvidenceRunError,
            "verified predecessor stage: clean-host-preflight",
        ):
            runner.execute_clean_install()

    def test_artifact_mutation_after_run_creation_is_not_treated_as_same_release(self) -> None:
        self.create_evidence_run()
        self.artifact.write_bytes(b"different package bytes")
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        with self.assertRaisesRegex(
            evidence_runner.MacOSCleanHostReleaseEvidenceRunError,
            "SHA-256 changed after evidence run creation",
        ):
            runner.record_artifact_integrity()
        self.assertIsNone(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(
                self.journal_path
            ).load_stage_record(evidence_runner.ARTIFACT_INTEGRITY_STAGE)
        )

    def test_developer_id_policy_rejects_an_explicit_unsigned_pkgutil_observation(self) -> None:
        evidence_run = replace(
            self.create_evidence_run(),
            macos_installer_signature_policy="developer-id",
        )
        issue = evidence_runner.evaluate_macos_installer_artifact_integrity_issue(
            evidence_run,
            self.available_installer_artifact_package_metadata_observation(),
            self.result(
                self.command_contract.pkgutil_executable,
                ["--check-signature", str(self.artifact)],
                1,
                "Package \"VitalServerRuntimePlatform\":\n   Status: no signature\n",
            ),
        )

        self.assertEqual("macos-package-signature-check-failed", issue["code"])

    def test_uninstall_reinstall_proves_explicit_c54_preservation_and_fresh_pkg_state(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.launchd_services_registered = True
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.assertEqual("verified", runner.record_reboot().status)
            lifecycle = runner.execute_uninstall_reinstall_preserving_data(
                self.host_installation_manager,
                self.installed_manifest,
                self.installation_journal,
                self.installation_receipt,
                self.removal_journal,
                self.removal_receipt,
                "remove-020",
                "vitalserver-runtime-platform-macos-reference",
                "runtime-platform-020",
            )

        self.assertEqual("verified", lifecycle.status)
        details = json.loads(lifecycle.evidence_path.read_text(encoding="utf-8"))["details"]
        self.assertEqual("preserve-mutable-data", details["dataDisposition"])
        self.assertEqual(
            "removed-by-host-installation-manager",
            details["hostProductRemovalReceipt"]["receipt"]["packageReceiptRemoval"],
        )
        contract_repository = ContractRepository(Path(__file__).resolve().parents[2])
        contract_repository.load()
        self.assertEqual(
            [],
            contract_repository.validate_instance(
                "release-delivery-proof.schema.json",
                {"schemaVersion": "v1", "proofs": [lifecycle.c24_proof]},
            ),
        )

    def test_uninstall_does_not_reinstall_without_a_matching_c54_receipt(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        def manager_with_invalid_removal_receipt(
            executable: Path, arguments: list[str]
        ) -> evidence_runner.MacOSCleanHostReleaseEvidenceCommandObservation:
            if executable == self.host_installation_manager:
                self.package_receipt_installed = False
                self.launchd_services_registered = False
                self.removal_journal.write_text("{}", encoding="utf-8")
                self.removal_receipt.write_text("{}", encoding="utf-8")
                return self.result(executable, arguments, 0, "C54 completed\n")
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=manager_with_invalid_removal_receipt,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.launchd_services_registered = True
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.assertEqual("verified", runner.record_reboot().status)
            lifecycle = runner.execute_uninstall_reinstall_preserving_data(
                self.host_installation_manager,
                self.installed_manifest,
                self.installation_journal,
                self.installation_receipt,
                self.removal_journal,
                self.removal_receipt,
                "remove-020",
                "vitalserver-runtime-platform-macos-reference",
                "runtime-platform-020",
            )

        self.assertEqual("failed", lifecycle.status)
        self.assertFalse(self.package_receipt_installed)
        self.assertEqual(1, self.installer_invocation_count)

    def test_stage_cannot_be_overwritten_by_a_second_collection_attempt(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ):
            runner.record_artifact_integrity()
            with self.assertRaisesRegex(
                evidence_runner.MacOSCleanHostReleaseEvidenceRunError,
                "evidence stage was already recorded: artifact-integrity",
            ):
                runner.record_artifact_integrity()

    def test_reads_uninstalled_flat_pkg_metadata_through_pkgutil_expansion(self) -> None:
        fake_pkgutil = self.root / "fake-pkgutil"
        fake_pkgutil.write_text(
            "#!/bin/sh\n"
            "if [ \"$1\" = \"--expand\" ]; then\n"
            "  mkdir -p \"$3\"\n"
            "  printf '%s\\n' '<pkg-info identifier=\"com.tirosh.vitalserver.runtime-platform\" version=\"0.2.0-dev\"/>' > \"$3/PackageInfo\"\n"
            "  exit 0\n"
            "fi\n"
            "exit 64\n",
            encoding="utf-8",
        )
        fake_pkgutil.chmod(0o755)

        observation = evidence_runner.observe_macos_installer_artifact_release_identity(
            fake_pkgutil, self.artifact
        )

        self.assertEqual("available", observation.state)
        self.assertEqual(
            "com.tirosh.vitalserver.runtime-platform",
            observation.package_identifier,
        )
        self.assertEqual("0.2.0-dev", observation.product_version)
        self.assertEqual(
            "--expand", observation.package_expansion_command.arguments[0]
        )


if __name__ == "__main__":
    unittest.main()
