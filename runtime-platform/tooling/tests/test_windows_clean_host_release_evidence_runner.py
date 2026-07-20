from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

from tooling import windows_clean_host_release_evidence_runner as evidence_runner
from tooling.contracts import ContractRepository


class WindowsCleanHostReleaseEvidenceRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.evidence_directory = self.root / "evidence"
        self.evidence_directory.mkdir()
        self.journal_path = self.root / "windows-clean-host.sqlite"
        self.artifact = self.root / "VitalServerRuntimePlatform-0.2.0.msi"
        self.artifact.write_bytes(b"selected msi bytes")
        self.product_installation_root = self.root / "ProgramData" / "VitalServerRuntimePlatform"
        self.product_immutable_release_root = (
            self.product_installation_root / "releases" / "runtime-platform-020"
        )
        self.product_data_root = self.product_installation_root / "data"
        self.commands = self.root / "commands"
        self.commands.mkdir()
        self.command_contract = evidence_runner.WindowsCleanHostReleaseEvidenceCommandContract(
            powershell_executable=self.executable("powershell.exe"),
            msiexec_executable=self.executable("msiexec.exe"),
            registry_executable=self.executable("reg.exe"),
            sc_executable=self.executable("sc.exe"),
        )
        self.msi_installed = False
        self.services_registered = False
        self.boot_session = "boot-before"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def executable(self, name: str) -> Path:
        path = self.commands / name
        path.write_text("fixture", encoding="utf-8")
        return path

    def create_evidence_run(self) -> evidence_runner.WindowsCleanHostReleaseEvidenceRun:
        return evidence_runner.create_windows_clean_host_release_evidence_run(
            journal_path=self.journal_path,
            evidence_directory=self.evidence_directory,
            installer_artifact_path=self.artifact,
            release_delivery_plans_document=(
                Path(__file__).resolve().parents[2]
                / "product"
                / "delivery"
                / "release-delivery-plans.v1.json"
            ),
            release_delivery_plan_id="windows-runtime-platform-release",
            run_id="windows-clean-host-001",
            runner_id="windows-host-fixture-001",
            msi_product_code="{A13CD872-E983-48BE-B20A-202607200002}",
            product_installation_root=self.product_installation_root,
            product_immutable_release_root=self.product_immutable_release_root,
            product_data_root=self.product_data_root,
            command_contract=self.command_contract,
        )

    @staticmethod
    def result(
        executable: Path,
        arguments: list[str],
        returncode: int,
        stdout: str = "",
        stderr: str = "",
    ) -> evidence_runner.windows_host_installation_observation.WindowsHostInstallationCommandObservation:
        return evidence_runner.windows_host_installation_observation.WindowsHostInstallationCommandObservation(
            executable=executable,
            arguments=tuple(arguments),
            returncode=returncode,
            stdout=stdout,
            stderr=stderr,
        )

    def command_result(
        self, executable: Path, arguments: list[str]
    ) -> evidence_runner.windows_host_installation_observation.WindowsHostInstallationCommandObservation:
        if executable == self.command_contract.powershell_executable:
            script = arguments[3]
            if script == evidence_runner.windows_host_installation_observation.WINDOWS_MSI_PRODUCT_VERSION_SCRIPT:
                return self.result(executable, arguments, 0, "0.2.0")
            if script == evidence_runner.windows_host_installation_observation.WINDOWS_MSI_SIGNATURE_SCRIPT:
                return self.result(executable, arguments, 0, '{"status":"Valid","statusMessage":"fixture"}')
            if script == evidence_runner.windows_host_installation_observation.WINDOWS_BOOT_SESSION_SCRIPT:
                return self.result(executable, arguments, 0, self.boot_session)
            if "Test-Path" in script:
                observed_path = Path(arguments[-1])
                return self.result(
                    executable,
                    arguments,
                    0,
                    "present" if observed_path.exists() else "absent",
                )
        if executable == self.command_contract.registry_executable:
            if self.msi_installed:
                return self.result(
                    executable,
                    arguments,
                    0,
                    "DisplayVersion    REG_SZ    0.2.0\n",
                )
            return self.result(
                executable,
                arguments,
                1,
                "",
                "ERROR: Unable to find the specified registry key or value.\n",
            )
        if executable == self.command_contract.sc_executable:
            if self.services_registered:
                return self.result(executable, arguments, 0, "SERVICE_NAME: " + arguments[1])
            return self.result(
                executable,
                arguments,
                1060,
                "",
                "The specified service does not exist as an installed service.\n",
            )
        if executable == self.command_contract.msiexec_executable:
            if arguments[0] == "/x":
                self.msi_installed = False
                self.services_registered = False
                shutil.rmtree(self.product_immutable_release_root)
                return self.result(executable, arguments, 0)
            self.msi_installed = True
            self.services_registered = True
            self.product_immutable_release_root.mkdir(parents=True)
            self.product_data_root.mkdir(parents=True, exist_ok=True)
            return self.result(executable, arguments, 0)
        raise AssertionError("unexpected command: " + str(executable) + " " + str(arguments))

    def test_collects_explicit_clean_host_install_service_and_reboot_evidence(self) -> None:
        evidence_run = self.create_evidence_run()
        self.assertEqual("VitalServerHostAgent", evidence_run.host_agent_windows_scm_service_name)
        self.assertEqual(
            "VitalServerHostUpdateHandoffSupervisor",
            evidence_run.host_update_handoff_supervisor_windows_scm_service_name,
        )
        runner = evidence_runner.WindowsCleanHostReleaseEvidenceRunner(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        with mock.patch.object(
            evidence_runner,
            "execute_windows_clean_host_command",
            side_effect=self.command_result,
        ):
            artifact_integrity = runner.record_artifact_integrity()
            preflight = runner.record_clean_host_preflight()
            clean_install = runner.execute_clean_install()
            self.services_registered = True
            service_registration = runner.record_service_registration()
            reboot_checkpoint = runner.record_reboot_checkpoint()
            self.boot_session = "boot-after"
            reboot = runner.record_reboot()

        self.assertEqual("verified", artifact_integrity.status)
        self.assertEqual("verified", preflight.status)
        self.assertEqual("verified", clean_install.status)
        self.assertEqual("verified", service_registration.status)
        self.assertEqual("verified", reboot_checkpoint.status)
        self.assertEqual("verified", reboot.status)
        self.assertEqual("msi", artifact_integrity.c24_proof["observedInstallerArtifact"]["kind"])
        self.assertEqual(
            ["host-agent", "host-edge-proxy", "host-update-handoff-supervisor"],
            [
                registration["role"]
                for registration in service_registration.c24_proof[
                    "observedHostServiceRegistrations"
                ]
            ],
        )
        contract_repository = ContractRepository(Path(__file__).resolve().parents[2])
        contract_repository.load()
        for stage_record in (
            artifact_integrity,
            clean_install,
            service_registration,
            reboot,
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
            evidence_runner.WindowsCleanHostReleaseEvidenceRunError,
            "output already exists",
        ):
            evidence_runner.write_new_c24_proof_fragment(
                proof_fragment_path, artifact_integrity
            )

    def test_preflight_does_not_treat_unknown_scm_error_as_a_clean_host(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.WindowsCleanHostReleaseEvidenceRunner(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        def command_with_unknown_scm_error(
            executable: Path, arguments: list[str]
        ) -> evidence_runner.windows_host_installation_observation.WindowsHostInstallationCommandObservation:
            if executable == self.command_contract.sc_executable:
                return self.result(executable, arguments, 1, "", "SCM RPC unavailable\n")
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_windows_clean_host_command",
            side_effect=command_with_unknown_scm_error,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            preflight = runner.record_clean_host_preflight()

        self.assertEqual("failed", preflight.status)
        self.assertEqual(
            "windows-clean-host-scm-service-observation-unavailable",
            json.loads(preflight.evidence_path.read_text(encoding="utf-8"))["issue"][
                "code"
            ],
        )
        with self.assertRaisesRegex(
            evidence_runner.WindowsCleanHostReleaseEvidenceRunError,
            "verified predecessor stage: clean-host-preflight",
        ):
            runner.execute_clean_install()

    def test_cli_requires_explicit_authorization_before_an_msi_effect(self) -> None:
        standard_error = io.StringIO()
        with mock.patch.object(evidence_runner, "require_windows_host_platform"), contextlib.redirect_stderr(standard_error):
            install_exit_code = evidence_runner.main(
                ["execute-clean-install", "--journal", str(self.journal_path)]
            )
            removal_exit_code = evidence_runner.main(
                [
                    "execute-uninstall-reinstall-preserving-data",
                    "--journal", str(self.journal_path),
                    "--removal-receipt", str(self.root / "removal-receipt.json"),
                    "--expected-removal-installation-id", "installation-001",
                    "--expected-removal-release-id", "release-001",
                ]
            )

        self.assertEqual(2, install_exit_code)
        self.assertEqual(2, removal_exit_code)
        self.assertIn("--authorize-clean-install", standard_error.getvalue())
        self.assertIn("--authorize-uninstall-reinstall", standard_error.getvalue())

    def test_records_host_platform_update_only_after_fresh_msi_scm_and_root_observations(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.WindowsCleanHostReleaseEvidenceRunner(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        transition = evidence_runner.host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence(
            stage="update",
            release_delivery_plan_id="windows-runtime-platform-release",
            platform="windows",
            provider_kind="windows-hyperv-scm",
            target_product_version="0.2.0",
            update_id="update-020",
            request_id="request-020",
            bootstrap_envelope_id="bootstrap-020",
            update_specification_sha256="b" * 64,
            host_platform_artifact_sha256="a" * 64,
            inputs=(),
            rollback_evidence=None,
            observed_installation_id="vitalserver-runtime-platform-windows",
            observed_release_id="runtime-platform-020",
            observed_product_version="0.2.0",
            observed_package_identifier="com.tirosh.vitalserver.runtime-platform",
            observed_at="2026-07-20T00:02:00Z",
        )
        with mock.patch.object(
            evidence_runner,
            "execute_windows_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner.host_platform_release_transition_evidence,
            "inspect_host_platform_update_transition",
            return_value=transition,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.boot_session = "boot-after"
            self.assertEqual("verified", runner.record_reboot().status)
            update = runner.record_host_platform_update(
                Path(__file__).resolve().parents[2] / "product" / "delivery" / "release-delivery-plans.v1.json",
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
            )

        self.assertEqual("verified", update.status)
        self.assertEqual("update", update.c24_proof["stage"])
        self.assertEqual(
            "0.2.0",
            json.loads(update.evidence_path.read_text(encoding="utf-8"))["details"]
            ["hostPlatformReleaseTransition"]["observedHostInstallation"]["productVersion"],
        )

    def test_msi_mutation_after_run_creation_is_not_treated_as_same_release(self) -> None:
        self.create_evidence_run()
        self.artifact.write_bytes(b"different msi bytes")
        runner = evidence_runner.WindowsCleanHostReleaseEvidenceRunner(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        with self.assertRaisesRegex(
            evidence_runner.WindowsCleanHostReleaseEvidenceRunError,
            "SHA-256 changed after evidence run creation",
        ):
            runner.record_artifact_integrity()
        self.assertIsNone(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(
                self.journal_path
            ).load_stage_record(evidence_runner.ARTIFACT_INTEGRITY_STAGE)
        )

    def test_transition_rejects_c23_document_that_changes_the_bound_scm_identity(self) -> None:
        evidence_run = self.create_evidence_run()
        plans_path = (
            Path(__file__).resolve().parents[2]
            / "product"
            / "delivery"
            / "release-delivery-plans.v1.json"
        )
        plans = json.loads(plans_path.read_text(encoding="utf-8"))
        selected = next(plan for plan in plans["plans"] if plan["id"] == "windows-runtime-platform-release")
        selected["requiredHostServiceRegistrations"][0]["name"] = "OtherHostAgent"
        changed_document = (self.root / "changed-release-delivery-plans.json").resolve()
        changed_document.write_text(json.dumps(plans), encoding="utf-8")

        issue = evidence_runner.transition_release_plan_issue(
            evidence_run, changed_document
        )

        self.assertEqual(
            "windows-host-platform-transition-release-plan-mismatch", issue["code"]
        )

    def test_run_rejects_a_mutable_data_root_that_is_not_distinct(self) -> None:
        with self.assertRaisesRegex(
            evidence_runner.WindowsCleanHostReleaseEvidenceRunError,
            "roots must be distinct",
        ):
            evidence_runner.create_windows_clean_host_release_evidence_run(
                journal_path=self.journal_path,
                evidence_directory=self.evidence_directory,
                installer_artifact_path=self.artifact,
                release_delivery_plans_document=(
                    Path(__file__).resolve().parents[2]
                    / "product"
                    / "delivery"
                    / "release-delivery-plans.v1.json"
                ),
                release_delivery_plan_id="windows-runtime-platform-release",
                run_id="windows-clean-host-001",
                runner_id="windows-host-fixture-001",
                msi_product_code="{A13CD872-E983-48BE-B20A-202607200002}",
                product_installation_root=self.product_installation_root,
                product_immutable_release_root=self.product_immutable_release_root,
                product_data_root=self.product_immutable_release_root,
                command_contract=self.command_contract,
            )

    def test_missing_update_handoff_supervisor_registration_fails_service_evidence(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.WindowsCleanHostReleaseEvidenceRunner(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        def command_with_missing_handoff_service(
            executable: Path, arguments: list[str]
        ) -> evidence_runner.windows_host_installation_observation.WindowsHostInstallationCommandObservation:
            if (
                executable == self.command_contract.sc_executable
                and arguments[1] == "VitalServerHostUpdateHandoffSupervisor"
                and self.services_registered
            ):
                return self.result(
                    executable,
                    arguments,
                    1060,
                    "",
                    "The specified service does not exist as an installed service.\n",
                )
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_windows_clean_host_command",
            side_effect=command_with_missing_handoff_service,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.services_registered = True
            registration = runner.record_service_registration()

        self.assertEqual("failed", registration.status)
        self.assertEqual(
            "windows-scm-service-registration-not-observed",
            registration.c24_proof["issue"]["code"],
        )

    def test_uninstall_reinstall_preserves_declared_data_only_after_completed_c54_receipt(
        self,
    ) -> None:
        self.create_evidence_run()
        runner = evidence_runner.WindowsCleanHostReleaseEvidenceRunner(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        removal_receipt = self.root / "completed-removal-receipt.json"
        removal_receipt.write_text(
            json.dumps(
                {
                    "schemaVersion": "v1",
                    "documentKind": "host-product-removal-receipt",
                    "id": "remove-020-receipt",
                    "requestId": "remove-020",
                    "installationId": "vitalserver-runtime-platform",
                    "releaseId": "runtime-platform-020",
                    "state": "completed",
                    "dataDisposition": "preserve-mutable-data",
                    "packageReceiptRemoval": "removed-by-os-package-manager",
                    "retainedMutableStoreIds": ["installation-data-root"],
                    "observedAt": "2026-07-20T00:00:00Z",
                }
            ),
            encoding="utf-8",
        )
        with mock.patch.object(
            evidence_runner,
            "execute_windows_clean_host_command",
            side_effect=self.command_result,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.services_registered = True
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.boot_session = "boot-after"
            self.assertEqual("verified", runner.record_reboot().status)
            lifecycle = runner.execute_uninstall_reinstall_preserving_data(
                removal_receipt.resolve(),
                "vitalserver-runtime-platform",
                "runtime-platform-020",
            )

        self.assertEqual("verified", lifecycle.status, lifecycle.c24_proof)
        details = json.loads(lifecycle.evidence_path.read_text(encoding="utf-8"))["details"]
        self.assertEqual("absent", details["immutableReleaseRoot"]["state"])
        self.assertEqual("present", details["mutableDataRoot"]["state"])
        self.assertEqual("present", details["postReinstall"]["immutableReleaseRoot"]["state"])

    def test_uninstall_does_not_reinstall_when_c54_receipt_is_invalid(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.WindowsCleanHostReleaseEvidenceRunner(
            evidence_runner.WindowsCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        removal_receipt = self.root / "wrong-removal-receipt.json"
        removal_receipt.write_text("{}", encoding="utf-8")
        with mock.patch.object(
            evidence_runner,
            "execute_windows_clean_host_command",
            side_effect=self.command_result,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.services_registered = True
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.boot_session = "boot-after"
            self.assertEqual("verified", runner.record_reboot().status)
            lifecycle = runner.execute_uninstall_reinstall_preserving_data(
                removal_receipt.resolve(),
                "vitalserver-runtime-platform",
                "runtime-platform-020",
            )

        self.assertEqual("failed", lifecycle.status)
        self.assertFalse(self.msi_installed)
        self.assertEqual(
            "windows-removal-receipt-does-not-prove-preserving-completion",
            lifecycle.c24_proof["issue"]["code"],
        )


if __name__ == "__main__":
    unittest.main()
