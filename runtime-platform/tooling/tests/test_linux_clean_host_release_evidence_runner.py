from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tooling import linux_clean_host_release_evidence_runner as evidence_runner
from tooling.contracts import ContractRepository


class LinuxCleanHostReleaseEvidenceRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.evidence_directory = self.root / "evidence"
        self.evidence_directory.mkdir()
        self.journal_path = self.root / "linux-clean-host.sqlite"
        self.artifact = self.root / "vitalserver-runtime-platform_0.2.0-dev_amd64.deb"
        self.artifact.write_bytes(b"selected deb bytes")
        self.product_root = self.root / "opt" / "vitalserver-runtime-platform"
        self.data_root = self.root / "var" / "lib" / "vitalserver-runtime-platform" / "data"
        self.commands = self.root / "commands"
        self.commands.mkdir()
        self.command_contract = evidence_runner.LinuxCleanHostReleaseEvidenceCommandContract(
            self.executable("dpkg-deb"),
            self.executable("dpkg"),
            self.executable("dpkg-query"),
            self.executable("systemctl"),
            self.executable("test"),
            self.executable("cat"),
            Path("/proc/sys/kernel/random/boot_id"),
        )
        self.package_installed = False
        self.services_registered = False
        self.boot_session = "linux-boot-before"
        self.installed_product_version = "0.2.0-dev"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def executable(self, name: str) -> Path:
        path = self.commands / name
        path.write_text("fixture", encoding="utf-8")
        return path

    def create_evidence_run(self) -> evidence_runner.LinuxCleanHostReleaseEvidenceRun:
        return evidence_runner.create_linux_clean_host_release_evidence_run(
            journal_path=self.journal_path,
            evidence_directory=self.evidence_directory,
            installer_artifact_path=self.artifact,
            release_delivery_plans_document=(
                Path(__file__).resolve().parents[2]
                / "product"
                / "delivery"
                / "release-delivery-plans.v1.json"
            ),
            release_delivery_plan_id="linux-runtime-platform-release",
            run_id="linux-clean-host-001",
            runner_id="linux-host-fixture-001",
            debian_package_identifier="com.tirosh.vitalserver.runtime-platform",
            product_installation_root=self.product_root,
            product_data_root=self.data_root,
            command_contract=self.command_contract,
        )

    @staticmethod
    def result(
        executable: Path,
        arguments: list[str],
        returncode: int,
        stdout: str = "",
        stderr: str = "",
    ) -> evidence_runner.linux_host_installation_observation.LinuxHostInstallationCommandObservation:
        return evidence_runner.linux_host_installation_observation.LinuxHostInstallationCommandObservation(
            executable=executable,
            arguments=tuple(arguments),
            returncode=returncode,
            stdout=stdout,
            stderr=stderr,
        )

    def command_result(
        self, executable: Path, arguments: list[str]
    ) -> evidence_runner.linux_host_installation_observation.LinuxHostInstallationCommandObservation:
        if executable == self.command_contract.dpkg_deb_executable:
            return self.result(
                executable,
                arguments,
                0,
                "com.tirosh.vitalserver.runtime-platform\n0.2.0-dev\n",
            )
        if executable == self.command_contract.dpkg_query_executable:
            if self.package_installed:
                return self.result(
                    executable, arguments, 0, "ii |" + self.installed_product_version + "\n"
                )
            return self.result(
                executable,
                arguments,
                1,
                "",
                "dpkg-query: no packages found matching com.tirosh.vitalserver.runtime-platform\n",
            )
        if executable == self.command_contract.systemctl_executable:
            return self.result(
                executable,
                arguments,
                0,
                "loaded\n" if self.services_registered else "not-found\n",
            )
        if executable == self.command_contract.test_executable:
            path = Path(arguments[1])
            return self.result(executable, arguments, 0 if path.exists() else 1)
        if executable == self.command_contract.cat_executable:
            return self.result(executable, arguments, 0, self.boot_session)
        if executable == self.command_contract.dpkg_executable:
            if arguments[0] == "--remove":
                self.package_installed = False
                self.services_registered = False
                self.product_root.rmdir()
                return self.result(executable, arguments, 0)
            self.package_installed = True
            self.services_registered = True
            self.product_root.mkdir(parents=True, exist_ok=True)
            self.data_root.mkdir(parents=True, exist_ok=True)
            return self.result(executable, arguments, 0)
        raise AssertionError("unexpected command: " + str(executable) + " " + str(arguments))

    def test_collects_explicit_clean_host_install_service_and_reboot_evidence(self) -> None:
        evidence_run = self.create_evidence_run()
        self.assertEqual(
            "vitalserver-host-update-handoff-supervisor.service",
            evidence_run.host_update_handoff_supervisor_systemd_service_name,
        )
        runner = evidence_runner.LinuxCleanHostReleaseEvidenceRunner(
            evidence_runner.LinuxCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        with mock.patch.object(
            evidence_runner,
            "execute_linux_clean_host_command",
            side_effect=self.command_result,
        ):
            artifact_integrity = runner.record_artifact_integrity()
            preflight = runner.record_clean_host_preflight()
            clean_install = runner.execute_clean_install()
            self.services_registered = True
            service_registration = runner.record_service_registration()
            reboot_checkpoint = runner.record_reboot_checkpoint()
            self.boot_session = "linux-boot-after"
            reboot = runner.record_reboot()

        self.assertEqual("verified", artifact_integrity.status)
        self.assertEqual("verified", preflight.status)
        self.assertEqual("verified", clean_install.status)
        self.assertEqual("verified", service_registration.status)
        self.assertEqual("verified", reboot_checkpoint.status)
        self.assertEqual("verified", reboot.status)
        self.assertEqual(
            ["host-agent", "host-edge-proxy", "host-update-handoff-supervisor"],
            [
                item["role"]
                for item in service_registration.c24_proof[
                    "observedHostServiceRegistrations"
                ]
            ],
        )
        repository = ContractRepository(Path(__file__).resolve().parents[2])
        repository.load()
        for stage in (artifact_integrity, clean_install, service_registration, reboot):
            self.assertEqual(
                [],
                repository.validate_instance(
                    "release-delivery-proof.schema.json",
                    {"schemaVersion": "v1", "proofs": [stage.c24_proof]},
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
            evidence_runner.LinuxCleanHostReleaseEvidenceRunError,
            "output already exists",
        ):
            evidence_runner.write_new_c24_proof_fragment(
                proof_fragment_path, artifact_integrity
            )

    def test_preflight_does_not_treat_unknown_systemd_error_as_absence(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.LinuxCleanHostReleaseEvidenceRunner(
            evidence_runner.LinuxCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        def command_with_unknown_systemd_error(
            executable: Path, arguments: list[str]
        ) -> evidence_runner.linux_host_installation_observation.LinuxHostInstallationCommandObservation:
            if executable == self.command_contract.systemctl_executable:
                return self.result(executable, arguments, 1, "", "systemd dbus unavailable\n")
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_linux_clean_host_command",
            side_effect=command_with_unknown_systemd_error,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            preflight = runner.record_clean_host_preflight()

        self.assertEqual("failed", preflight.status)
        self.assertEqual(
            "linux-clean-host-systemd-service-not-absent",
            json.loads(preflight.evidence_path.read_text(encoding="utf-8"))["issue"]["code"],
        )
        with self.assertRaisesRegex(
            evidence_runner.LinuxCleanHostReleaseEvidenceRunError,
            "verified predecessor stage: clean-host-preflight",
        ):
            runner.execute_clean_install()

    def test_cli_requires_explicit_authorization_before_a_deb_effect(self) -> None:
        standard_error = io.StringIO()
        with mock.patch.object(evidence_runner, "require_linux_host_platform"), contextlib.redirect_stderr(standard_error):
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

    def test_records_rollback_against_the_restored_c48_version_not_c23_target(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.LinuxCleanHostReleaseEvidenceRunner(
            evidence_runner.LinuxCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        rollback_transition = evidence_runner.host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence(
            stage="rollback",
            release_delivery_plan_id="linux-runtime-platform-release",
            platform="linux",
            provider_kind="linux-kvm-libvirt-systemd",
            target_product_version="0.2.0-dev",
            update_id="update-020",
            request_id="request-020",
            bootstrap_envelope_id="bootstrap-020",
            update_specification_sha256="b" * 64,
            host_platform_artifact_sha256="a" * 64,
            inputs=(),
            rollback_evidence={"kind": "staged-update-rollback", "id": "update-020:rollback"},
            observed_installation_id="vitalserver-runtime-platform-linux",
            observed_release_id="runtime-platform-010",
            observed_product_version="0.1.0",
            observed_package_identifier="com.tirosh.vitalserver.runtime-platform",
            observed_at="2026-07-20T00:02:00Z",
        )
        with mock.patch.object(
            evidence_runner,
            "execute_linux_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner.host_platform_release_transition_evidence,
            "inspect_host_platform_rollback_transition",
            return_value=rollback_transition,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.boot_session = "linux-boot-after"
            self.assertEqual("verified", runner.record_reboot().status)
            self.installed_product_version = "0.1.0"
            rollback = runner.record_host_platform_rollback(
                Path(__file__).resolve().parents[2] / "product" / "delivery" / "release-delivery-plans.v1.json",
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
            )

        self.assertEqual("verified", rollback.status)
        self.assertEqual("rollback", rollback.c24_proof["stage"])

    def test_records_update_only_with_transition_and_fresh_os_facts(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.LinuxCleanHostReleaseEvidenceRunner(
            evidence_runner.LinuxCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        def transition(stage: str, observed_product_version: str):
            return evidence_runner.host_platform_release_transition_evidence.HostPlatformReleaseTransitionEvidence(
                stage=stage,
                release_delivery_plan_id="linux-runtime-platform-release",
                platform="linux",
                provider_kind="linux-kvm-libvirt-systemd",
                target_product_version="0.2.0-dev",
                update_id="update-020",
                request_id="request-020",
                bootstrap_envelope_id="bootstrap-020",
                update_specification_sha256="b" * 64,
                host_platform_artifact_sha256="a" * 64,
                inputs=(),
                rollback_evidence=(
                    {"kind": "staged-update-rollback", "id": "update-020:rollback"}
                    if stage == "rollback"
                    else None
                ),
                observed_installation_id="vitalserver-runtime-platform-linux",
                observed_release_id="runtime-platform-020",
                observed_product_version=observed_product_version,
                observed_package_identifier="com.tirosh.vitalserver.runtime-platform",
                observed_at="2026-07-20T00:02:00Z",
            )

        with mock.patch.object(
            evidence_runner,
            "execute_linux_clean_host_command",
            side_effect=self.command_result,
        ), mock.patch.object(
            evidence_runner.host_platform_release_transition_evidence,
            "inspect_host_platform_update_transition",
            return_value=transition("update", "0.2.0-dev"),
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.boot_session = "linux-boot-after"
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
            "0.2.0-dev",
            json.loads(update.evidence_path.read_text(encoding="utf-8"))["details"]
            ["hostPlatformReleaseTransition"]["observedHostInstallation"]["productVersion"],
        )
        with self.assertRaisesRegex(
            evidence_runner.LinuxCleanHostReleaseEvidenceRunError,
            "cannot mix update and rollback",
        ):
            runner.record_host_platform_rollback(
                Path(__file__).resolve().parents[2] / "product" / "delivery" / "release-delivery-plans.v1.json",
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
                self.artifact.resolve(),
            )

    def test_deb_mutation_after_run_creation_is_not_treated_as_same_release(self) -> None:
        self.create_evidence_run()
        self.artifact.write_bytes(b"different deb bytes")
        runner = evidence_runner.LinuxCleanHostReleaseEvidenceRunner(
            evidence_runner.LinuxCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        with self.assertRaisesRegex(
            evidence_runner.LinuxCleanHostReleaseEvidenceRunError,
            "SHA-256 changed after evidence run creation",
        ):
            runner.record_artifact_integrity()

    def test_transition_rejects_c23_document_that_changes_the_bound_systemd_identity(self) -> None:
        evidence_run = self.create_evidence_run()
        plans = json.loads(
            (
                Path(__file__).resolve().parents[2]
                / "product"
                / "delivery"
                / "release-delivery-plans.v1.json"
            ).read_text(encoding="utf-8")
        )
        selected = next(plan for plan in plans["plans"] if plan["id"] == "linux-runtime-platform-release")
        selected["requiredHostServiceRegistrations"][0]["name"] = "other-host-agent.service"
        changed_document = (self.root / "changed-release-delivery-plans.json").resolve()
        changed_document.write_text(json.dumps(plans), encoding="utf-8")

        issue = evidence_runner.transition_release_plan_issue(
            evidence_run, changed_document
        )

        self.assertEqual(
            "linux-host-platform-transition-release-plan-mismatch", issue["code"]
        )

    def test_uninstall_reinstall_proves_explicit_c54_preservation_and_fresh_os_state(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.LinuxCleanHostReleaseEvidenceRunner(
            evidence_runner.LinuxCleanHostReleaseEvidenceJournal(self.journal_path)
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
                    "dataDisposition": "preserve-mutable-data",
                    "state": "completed",
                    "packageReceiptRemoval": "removed-by-os-package-manager",
                    "retainedMutableStoreIds": ["native-machine-runtime"],
                    "observedAt": "2026-07-20T00:03:00Z",
                }
            ),
            encoding="utf-8",
        )
        with mock.patch.object(
            evidence_runner,
            "execute_linux_clean_host_command",
            side_effect=self.command_result,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.services_registered = True
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.boot_session = "linux-boot-after"
            self.assertEqual("verified", runner.record_reboot().status)
            lifecycle = runner.execute_uninstall_reinstall_preserving_data(
                removal_receipt.resolve(),
                "vitalserver-runtime-platform",
                "runtime-platform-020",
            )

        self.assertEqual(
            "verified",
            lifecycle.status,
            lifecycle.evidence_path.read_text(encoding="utf-8"),
        )
        details = json.loads(lifecycle.evidence_path.read_text(encoding="utf-8"))["details"]
        self.assertEqual("preserve-mutable-data", details["dataDisposition"])
        self.assertEqual(
            "removed-by-os-package-manager",
            details["hostProductRemovalReceipt"]["receipt"]["packageReceiptRemoval"],
        )
        repository = ContractRepository(Path(__file__).resolve().parents[2])
        repository.load()
        self.assertEqual(
            [],
            repository.validate_instance(
                "release-delivery-proof.schema.json",
                {"schemaVersion": "v1", "proofs": [lifecycle.c24_proof]},
            ),
        )

    def test_uninstall_does_not_reinstall_after_an_unrelated_or_missing_c54_receipt(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.LinuxCleanHostReleaseEvidenceRunner(
            evidence_runner.LinuxCleanHostReleaseEvidenceJournal(self.journal_path)
        )
        removal_receipt = self.root / "wrong-removal-receipt.json"
        removal_receipt.write_text("{}", encoding="utf-8")
        with mock.patch.object(
            evidence_runner,
            "execute_linux_clean_host_command",
            side_effect=self.command_result,
        ):
            self.assertEqual("verified", runner.record_artifact_integrity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_clean_install().status)
            self.services_registered = True
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.boot_session = "linux-boot-after"
            self.assertEqual("verified", runner.record_reboot().status)
            lifecycle = runner.execute_uninstall_reinstall_preserving_data(
                removal_receipt.resolve(),
                "vitalserver-runtime-platform",
                "runtime-platform-020",
            )

        self.assertEqual("failed", lifecycle.status)
        self.assertFalse(self.package_installed)
        self.assertFalse(self.product_root.exists())


if __name__ == "__main__":
    unittest.main()
