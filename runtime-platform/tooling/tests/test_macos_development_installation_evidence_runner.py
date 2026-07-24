"""Command-contract tests for unsigned macOS development-installation evidence."""

from __future__ import annotations

from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest import mock

from tooling import macos_development_installation_evidence_runner as evidence_runner
from tooling import macos_host_installation_observation


class MacOSDevelopmentInstallationEvidenceRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.evidence_directory = self.root / "evidence"
        self.evidence_directory.mkdir()
        self.artifact = self.root / "VitalServerRuntimePlatform-0.2.0-dev.pkg"
        self.artifact.write_bytes(b"unsigned development package bytes")
        self.journal_path = self.root / "development-installation-evidence.sqlite"
        self.installed_supervisor = (
            Path("/Library/Application Support/VitalServerRuntimePlatform/bin")
            / "macos-virtual-machine-supervisor"
        )
        self.release_delivery_plans_document = (
            Path(__file__).resolve().parents[2]
            / "product"
            / "delivery"
            / "release-delivery-plans.v1.json"
        )
        self.command_contract = (
            evidence_runner.MacOSDevelopmentInstallationCommandContract(
                pkgutil_executable=Path("/usr/sbin/pkgutil"),
                installer_executable=Path("/usr/sbin/installer"),
                launchctl_executable=Path("/bin/launchctl"),
                codesign_executable=Path("/usr/bin/codesign"),
                sysctl_executable=Path("/usr/sbin/sysctl"),
            )
        )
        self.package_receipt_installed = False
        self.launchd_services_registered = False
        self.signature_state = "ad-hoc"
        self.boot_session_identifiers = iter(("development-boot-before", "development-boot-after"))

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def create_evidence_run(self) -> evidence_runner.MacOSDevelopmentInstallationEvidenceRun:
        return evidence_runner.create_macos_development_installation_evidence_run(
            journal_path=self.journal_path,
            evidence_directory=self.evidence_directory,
            installer_artifact_path=self.artifact,
            installed_virtual_machine_supervisor_path=self.installed_supervisor,
            release_delivery_plans_document=self.release_delivery_plans_document,
            release_delivery_plan_id="macos-runtime-platform-release",
            run_id="macos-development-installation-01",
            runner_id="macos-development-runner-01",
            command_contract=self.command_contract,
        )

    def result(
        self,
        executable: Path,
        arguments: list[str],
        returncode: int,
        stdout: str = "",
        stderr: str = "",
    ) -> macos_host_installation_observation.MacOSHostInstallationCommandObservation:
        return macos_host_installation_observation.MacOSHostInstallationCommandObservation(
            executable=executable,
            arguments=tuple(arguments),
            returncode=returncode,
            stdout=stdout,
            stderr=stderr,
        )

    def command_result(
        self,
        executable: Path,
        arguments: list[str],
    ) -> macos_host_installation_observation.MacOSHostInstallationCommandObservation:
        if executable == self.command_contract.pkgutil_executable:
            if arguments[0] == "--expand":
                expansion_directory = Path(arguments[2])
                expansion_directory.mkdir(parents=True)
                (expansion_directory / "PackageInfo").write_text(
                    '<pkg-info identifier="com.tirosh.vitalserver.runtime-platform" version="0.2.0-dev"/>',
                    encoding="utf-8",
                )
                return self.result(executable, arguments, 0)
            if arguments[0] == "--check-signature":
                return self.result(
                    executable,
                    arguments,
                    1,
                    'Package "VitalServerRuntimePlatform":\n   Status: no signature\n',
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
                    stderr="No receipt for 'com.tirosh.vitalserver.runtime-platform' found at '/'.\n",
                )
        if executable == self.command_contract.installer_executable:
            self.package_receipt_installed = True
            self.launchd_services_registered = True
            return self.result(executable, arguments, 0, "installer: The install was successful.\n")
        if executable == self.command_contract.launchctl_executable:
            if self.launchd_services_registered:
                return self.result(executable, arguments, 0, "service = registered\n")
            service_label = arguments[1].removeprefix("system/")
            return self.result(
                executable,
                arguments,
                113,
                stderr='Could not find service "' + service_label + '" in domain for system\n',
            )
        if executable == self.command_contract.codesign_executable:
            if arguments[0] == "--verify":
                return self.result(executable, arguments, 0)
            if arguments[0] == "--display" and "--entitlements" in arguments:
                return self.result(
                    executable,
                    arguments,
                    0,
                    '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>com.apple.security.virtualization</key><true/></dict></plist>',
                )
            if arguments[0] == "--display":
                if self.signature_state == "ad-hoc":
                    return self.result(executable, arguments, 0, "Signature=adhoc\n")
                if self.signature_state == "developer-id":
                    return self.result(
                        executable,
                        arguments,
                        0,
                        "Authority=Developer ID Application: Tirosh\n",
                    )
        if executable == self.command_contract.sysctl_executable:
            return self.result(executable, arguments, 0, next(self.boot_session_identifiers) + "\n")
        raise AssertionError("unexpected command: " + str(executable) + " " + str(arguments))

    def runner(self) -> evidence_runner.MacOSDevelopmentInstallationEvidenceRunner:
        return evidence_runner.MacOSDevelopmentInstallationEvidenceRunner(
            evidence_runner.MacOSDevelopmentInstallationEvidenceJournal(
                self.journal_path
            )
        )

    def test_unsigned_package_and_ad_hoc_supervisor_record_development_evidence_without_c24(self) -> None:
        self.create_evidence_run()
        runner = self.runner()

        with mock.patch.object(
            evidence_runner,
            "execute_macos_development_installation_command",
            side_effect=self.command_result,
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0):
            self.assertEqual("verified", runner.record_artifact_identity().status)
            self.assertEqual("verified", runner.record_clean_host_preflight().status)
            self.assertEqual("verified", runner.execute_installation().status)
            self.assertEqual("verified", runner.record_service_registration().status)
            self.assertEqual("verified", runner.record_supervisor_signature().status)
            self.assertEqual("verified", runner.record_reboot_checkpoint().status)
            self.assertEqual("verified", runner.record_reboot().status)

        journal = evidence_runner.MacOSDevelopmentInstallationEvidenceJournal(
            self.journal_path
        )
        for stage in (
            evidence_runner.ARTIFACT_IDENTITY_STAGE,
            evidence_runner.CLEAN_HOST_PREFLIGHT_STAGE,
            evidence_runner.INSTALLATION_STAGE,
            evidence_runner.SERVICE_REGISTRATION_STAGE,
            evidence_runner.SUPERVISOR_SIGNATURE_STAGE,
            evidence_runner.REBOOT_CHECKPOINT_STAGE,
            evidence_runner.REBOOT_STAGE,
        ):
            self.assertEqual("verified", journal.load_stage_record(stage).status)
        artifact_evidence = json.loads(
            (self.evidence_directory / "artifact-identity.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual("development-installation", artifact_evidence["purpose"])
        self.assertNotIn("c24", json.dumps(artifact_evidence, sort_keys=True).lower())
        self.assertEqual(
            1,
            artifact_evidence["details"]["packageSignatureCommand"]["returnCode"],
        )
        service_evidence = json.loads(
            (self.evidence_directory / "service-registration.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            [
                "host-agent",
                "host-edge-proxy",
                "host-update-handoff-supervisor",
            ],
            [
                observation["role"]
                for observation in service_evidence["details"][
                    "launchdServiceRegistrationObservations"
                ]
            ],
        )
        supervisor_evidence = json.loads(
            (self.evidence_directory / "supervisor-signature.json").read_text(
                encoding="utf-8"
            )
        )
        signature = supervisor_evidence["details"][
            "virtualMachineSupervisorCodeSignatureObservation"
        ]
        self.assertEqual("ad-hoc", signature["signatureState"])
        self.assertEqual("present", signature["virtualizationEntitlementState"])

    def test_signed_package_does_not_become_unsigned_development_artifact_evidence(self) -> None:
        self.create_evidence_run()
        runner = self.runner()

        def command_with_signed_package(
            executable: Path,
            arguments: list[str],
        ) -> macos_host_installation_observation.MacOSHostInstallationCommandObservation:
            if (
                executable == self.command_contract.pkgutil_executable
                and arguments[0] == "--check-signature"
            ):
                return self.result(
                    executable,
                    arguments,
                    0,
                    'Package "VitalServerRuntimePlatform":\n   Status: signed by a developer certificate\n',
                )
            return self.command_result(executable, arguments)

        with mock.patch.object(
            evidence_runner,
            "execute_macos_development_installation_command",
            side_effect=command_with_signed_package,
        ):
            stage = runner.record_artifact_identity()

        self.assertEqual("failed", stage.status)
        evidence = json.loads(stage.evidence_path.read_text(encoding="utf-8"))
        self.assertEqual(
            "macos-development-package-is-not-unsigned",
            evidence["issue"]["code"],
        )
        self.assertIsNone(
            evidence_runner.MacOSDevelopmentInstallationEvidenceJournal(
                self.journal_path
            ).load_stage_record(evidence_runner.CLEAN_HOST_PREFLIGHT_STAGE)
        )

    def test_developer_id_supervisor_is_not_ad_hoc_development_evidence(self) -> None:
        self.create_evidence_run()
        runner = self.runner()
        self.signature_state = "developer-id"

        with mock.patch.object(
            evidence_runner,
            "execute_macos_development_installation_command",
            side_effect=self.command_result,
        ), mock.patch.object(evidence_runner.os, "geteuid", return_value=0):
            runner.record_artifact_identity()
            runner.record_clean_host_preflight()
            runner.execute_installation()
            runner.record_service_registration()
            stage = runner.record_supervisor_signature()

        self.assertEqual("failed", stage.status)
        evidence = json.loads(stage.evidence_path.read_text(encoding="utf-8"))
        self.assertEqual(
            "macos-development-supervisor-signature-not-ad-hoc",
            evidence["issue"]["code"],
        )

    def test_stage_cannot_be_overwritten_after_artifact_bytes_change(self) -> None:
        self.create_evidence_run()
        runner = self.runner()
        self.artifact.write_bytes(b"different package bytes")

        with self.assertRaisesRegex(
            evidence_runner.MacOSDevelopmentInstallationEvidenceRunError,
            "SHA-256 changed after evidence run creation",
        ):
            runner.record_artifact_identity()
        self.assertIsNone(
            evidence_runner.MacOSDevelopmentInstallationEvidenceJournal(
                self.journal_path
            ).load_stage_record(evidence_runner.ARTIFACT_IDENTITY_STAGE)
        )

    def test_pre_update_handoff_development_evidence_journal_cannot_be_resumed(self) -> None:
        with closing(sqlite3.connect(self.journal_path)) as connection:
            connection.execute(
                "CREATE TABLE development_installation_run (run_id TEXT NOT NULL)"
            )
            connection.commit()

        with self.assertRaisesRegex(
            evidence_runner.MacOSDevelopmentInstallationEvidenceRunError,
            "Host Update Handoff Supervisor service",
        ):
            evidence_runner.MacOSDevelopmentInstallationEvidenceJournal(
                self.journal_path
            ).load_evidence_run()


if __name__ == "__main__":
    unittest.main()
