"""Release-process tests for macOS clean-Host C24 evidence collection."""

from __future__ import annotations

import json
from pathlib import Path
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
        self.command_contract = (
            evidence_runner.MacOSCleanHostReleaseEvidenceCommandContract(
                pkgutil_executable=Path("/usr/sbin/pkgutil"),
                installer_executable=Path("/usr/sbin/installer"),
                launchctl_executable=Path("/bin/launchctl"),
                sysctl_executable=Path("/usr/sbin/sysctl"),
            )
        )
        self.package_receipt_installed = False
        self.launchd_services_registered = False
        self.boot_session_identifiers = iter(("boot-session-before", "boot-session-after"))

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

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
                    0,
                    "Package \"VitalServerRuntimePlatform\":\n   Status: signed by a developer certificate issued by Apple for distribution\n",
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
            self.package_receipt_installed = True
            return self.result(executable, arguments, 0, "installer: completed\n")
        if executable == self.command_contract.launchctl_executable:
            if self.launchd_services_registered:
                return self.result(executable, arguments, 0, "service = registered\n")
            return self.result(
                executable,
                arguments,
                113,
                "",
                "Could not find service \"" + arguments[1] + "\" in domain for system\n",
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

    def test_collects_explicit_clean_host_install_service_and_reboot_evidence(self) -> None:
        evidence_run = self.create_evidence_run()
        self.assertEqual(
            "com.tirosh.vitalserver.runtime-platform",
            evidence_run.macos_installer_package_identifier,
        )

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

        self.assertEqual("verified", artifact_integrity.status)
        self.assertEqual("verified", clean_host_preflight.status)
        self.assertEqual("verified", clean_install.status)
        self.assertEqual("verified", service_registration.status)
        self.assertEqual("verified", reboot_checkpoint.status)
        self.assertEqual("verified", reboot.status)
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
            ["host-agent", "host-edge-proxy"],
            [
                registration["role"]
                for registration in service_registration.c24_proof[
                    "observedHostServiceRegistrations"
                ]
            ],
        )
        self.assertEqual("reboot", reboot.c24_proof["stage"])
        contract_repository = ContractRepository(
            Path(__file__).resolve().parents[2]
        )
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
        self.assertNotEqual(
            json.loads(
                reboot_checkpoint.evidence_path.read_text(encoding="utf-8")
            )["details"]["bootSessionObservation"]["bootSessionIdentifier"],
            json.loads(reboot.evidence_path.read_text(encoding="utf-8"))["details"][
                "postRebootBootSessionObservation"
            ]["bootSessionIdentifier"],
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

    def test_unsigned_pkgutil_observation_records_a_failed_artifact_integrity_proof(self) -> None:
        self.create_evidence_run()
        runner = evidence_runner.MacOSCleanHostReleaseEvidenceRunner(
            evidence_runner.MacOSCleanHostReleaseEvidenceJournal(self.journal_path)
        )

        def command_with_unsigned_package(
            executable: Path, arguments: list[str]
        ) -> evidence_runner.MacOSCleanHostReleaseEvidenceCommandObservation:
            if (
                executable == self.command_contract.pkgutil_executable
                and arguments[0] == "--check-signature"
            ):
                return self.result(
                    executable,
                    arguments,
                    0,
                    "Package \"VitalServerRuntimePlatform\":\n   Status: no signature\n",
                )
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_macos_clean_host_command",
            side_effect=command_with_unsigned_package,
        ), mock.patch.object(
            evidence_runner,
            "observe_macos_installer_artifact_release_identity",
            return_value=self.available_installer_artifact_package_metadata_observation(),
        ):
            artifact_integrity = runner.record_artifact_integrity()

        self.assertEqual("failed", artifact_integrity.status)
        self.assertEqual(
            "macos-package-signature-not-accepted",
            artifact_integrity.c24_proof["issue"]["code"],
        )
        self.assertEqual(
            "macos-package-signature-not-accepted",
            json.loads(artifact_integrity.evidence_path.read_text(encoding="utf-8"))["issue"][
                "code"
            ],
        )

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
