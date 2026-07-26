"""Tests for C78 installed Guest evidence ownership and reboot policy."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tooling import guest_installed_runtime_evidence_runner as runner
from tooling.contracts import ContractRepository


class GuestInstalledRuntimeEvidenceRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.repository_root = Path(__file__).resolve().parents[2]
        self.evidence_directory = self.root / "evidence"
        self.evidence_directory.mkdir()
        self.platformctl = self.executable("platformctl")
        self.sysctl = self.executable("sysctl")
        self.curl = self.executable("curl")
        self.source_vital_file = self.root / "synthetic-release-evidence.vital"
        self.source_vital_file.write_bytes(b"synthetic-vital-release-evidence")
        self.descriptor = self.root / "local-control.json"
        self.descriptor.write_text("{}", encoding="utf-8")
        self.journal_path = self.root / "c78.sqlite"
        self.identity = json.loads(
            (
                self.repository_root
                / "contracts"
                / "examples"
                / "v1"
                / "valid"
                / "guest-operational-state-identity.json"
            ).read_text(encoding="utf-8")
        )
        self.artifact_detail = json.loads(
            (
                self.repository_root
                / "contracts"
                / "examples"
                / "v1"
                / "valid"
                / "archive-artifact-detail.json"
            ).read_text(encoding="utf-8")
        )
        run = runner.EvidenceRun(
            run_id="guest-installed-run-1",
            runner_id="macos-clean-host-runner-1",
            release_delivery_plan_id="macos-runtime-platform-release",
            platformctl_executable=self.platformctl,
            local_control_descriptor=self.descriptor,
            sysctl_executable=self.sysctl,
            contract_root=self.repository_root,
            evidence_directory=self.evidence_directory,
            created_at="2026-07-24T23:30:00Z",
        )
        self.journal = runner.Journal.create(self.journal_path, run)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def executable(self, name: str) -> Path:
        path = self.root / name
        path.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        path.chmod(0o755)
        return path

    def observation(
        self,
        executable: Path,
        arguments: tuple[str, ...],
        returncode: int,
        stdout: str,
        stderr: str = "",
    ) -> runner.CommandObservation:
        return runner.CommandObservation(
            executable=executable,
            arguments=arguments,
            returncode=returncode,
            stdout=stdout,
            stderr=stderr,
        )

    def command_side_effect(
        self,
        boot_sessions: list[str],
        identities: list[dict],
        readiness_state: str = "available",
    ):
        sessions = iter(boot_sessions)
        identity_documents = iter(identities)

        def execute(
            executable: Path,
            arguments: tuple[str, ...],
        ) -> runner.CommandObservation:
            if executable == self.sysctl:
                return self.observation(
                    executable,
                    arguments,
                    0,
                    next(sessions) + "\n",
                )
            if arguments[-2:] == ("runtime", "readiness"):
                return self.observation(
                    executable,
                    arguments,
                    0,
                    json.dumps(
                        {
                            "httpStatus": 200,
                            "document": {
                                "schemaVersion": "v1",
                                "state": readiness_state,
                                "observedAt": "2026-07-24T23:29:59Z",
                                "value": {
                                    "schemaVersion": "v1",
                                    "service": {
                                        "name": "guest-runtime",
                                        "version": "0.2.0",
                                        "instanceId": "guest-runtime-primary",
                                    },
                                    "state": "ready",
                                    "observedAt": "2026-07-24T23:29:59Z",
                                },
                            },
                        }
                    ),
                )
            if arguments[-2:] == (
                "runtime",
                "operational-state-identity",
            ):
                return self.observation(
                    executable,
                    arguments,
                    0,
                    json.dumps(
                        {
                            "httpStatus": 200,
                            "document": {
                                "schemaVersion": "v1",
                                "state": "available",
                                "observedAt": "2026-07-24T23:29:59Z",
                                "value": next(identity_documents),
                            },
                        }
                    ),
                )
            self.fail("unexpected command: " + repr((executable, arguments)))

        return execute

    def direct_upload_owner_documents(self) -> tuple[dict, dict, dict]:
        run = self.journal.load_run()
        _, assignment_evidence_id = runner.direct_upload_assignment_ids(
            run.run_id
        )
        source_sha256 = runner.sha256_file(self.source_vital_file)
        source_size = self.source_vital_file.stat().st_size
        source_receipt_id = "recorder-vital-upload-c78-upload-1"
        detail = copy.deepcopy(self.artifact_detail)
        artifact = detail["artifact"]
        artifact["sourceReceiptType"] = runner.RECORDER_UPLOAD_RECEIPT_TYPE
        artifact["sourceReceiptId"] = source_receipt_id
        artifact["originalFileName"] = self.source_vital_file.name
        artifact["byteSize"] = source_size
        artifact["sha256"] = source_sha256
        artifact["manifest"]["source"]["receiptType"] = (
            runner.RECORDER_UPLOAD_RECEIPT_TYPE
        )
        artifact["manifest"]["source"]["receiptId"] = source_receipt_id
        artifact["manifest"]["source"]["evidenceReference"] = {
            "kind": runner.RECORDER_UPLOAD_RECEIPT_TYPE,
            "id": source_receipt_id,
        }
        artifact["manifest"]["artifact"]["artifactId"] = artifact["artifactId"]
        artifact["manifest"]["artifact"]["byteSize"] = source_size
        artifact["manifest"]["artifact"]["sha256"] = source_sha256
        attribution = detail["attribution"]
        attribution["reportedBedName"] = "OR-01"
        attribution["assignmentEvidenceReference"] = {
            "kind": "recorder-assignment-evidence",
            "id": assignment_evidence_id,
        }
        attribution["candidateRecorderIds"] = ["recorder-1"]
        attribution["outcome"] = "matched"
        attribution["matchedRecorderId"] = "recorder-1"
        request_id, evidence_id = runner.direct_upload_assignment_ids(
            run.run_id
        )
        assignment_receipt = {
            "schemaVersion": "v1",
            "requestId": request_id,
            "outcome": "accepted",
            "evidenceReference": {
                "kind": "recorder-assignment-evidence",
                "id": evidence_id,
            },
            "persistedAt": "2026-07-24T23:30:01Z",
        }
        artifact_page = {
            "schemaVersion": "v1",
            "recorderId": "recorder-1",
            "items": [detail],
        }
        return assignment_receipt, artifact_page, detail

    def direct_upload_command_side_effect(
        self,
        assignment_receipt: dict,
        artifact_page: dict,
        artifact_detail: dict,
    ):
        def execute(
            executable: Path,
            arguments: tuple[str, ...],
        ) -> runner.CommandObservation:
            if "assignment" in arguments:
                return self.observation(
                    executable,
                    arguments,
                    0,
                    json.dumps(
                        {
                            "httpStatus": 202,
                            "document": assignment_receipt,
                        }
                    ),
                )
            if "artifacts" in arguments:
                return self.observation(
                    executable,
                    arguments,
                    0,
                    json.dumps(
                        {
                            "httpStatus": 200,
                            "document": {
                                "schemaVersion": "v1",
                                "state": "available",
                                "observedAt": "2026-07-24T23:30:02Z",
                                "value": artifact_page,
                            },
                        }
                    ),
                )
            if "artifact" in arguments:
                return self.observation(
                    executable,
                    arguments,
                    0,
                    json.dumps(
                        {
                            "httpStatus": 200,
                            "document": {
                                "schemaVersion": "v1",
                                "state": "available",
                                "observedAt": "2026-07-24T23:30:03Z",
                                "value": artifact_detail,
                            },
                        }
                    ),
                )
            self.fail("unexpected direct-upload command: " + repr(arguments))

        return execute

    def record_verified_direct_upload(
        self,
        workflow: runner.Runner,
    ) -> runner.StageRecord:
        assignment, page, detail = self.direct_upload_owner_documents()
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.direct_upload_command_side_effect(
                assignment,
                page,
                detail,
            ),
        ), mock.patch.object(
            runner,
            "execute_upload_command",
            return_value=self.observation(
                self.curl,
                ("upload",),
                0,
                "success",
            ),
        ):
            return workflow.record_direct_upload(
                self.source_vital_file,
                "http://edge",
                "recorder-1",
                "OR-01",
                "VR-01",
                "c78-upload-1",
                self.curl,
            )

    def test_records_verified_first_boot_and_unchanged_post_reboot_identity(
        self,
    ) -> None:
        workflow = runner.Runner(self.journal)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-a", "boot-a", "boot-b", "boot-b"],
                [self.identity, self.identity],
            ),
        ):
            checkpoint = workflow.record_first_boot()
        direct_upload = self.record_verified_direct_upload(workflow)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-b", "boot-b"],
                [self.identity],
            ),
        ):
            reboot = workflow.record_post_reboot()
        self.assertEqual("verified", checkpoint.status)
        self.assertEqual("verified", direct_upload.status)
        self.assertEqual("verified", reboot.status)
        reboot_document = self.journal.load_stage_document(
            runner.POST_REBOOT_STAGE
        )
        self.assertEqual(
            checkpoint.evidence_id,
            reboot_document["checkpointEvidenceId"],
        )
        self.assertEqual(
            direct_upload.evidence_id,
            reboot_document["directUploadEvidenceId"],
        )
        self.assertEqual("boot-b", reboot_document["hostBootSessionIdentifier"])
        contract_repository = ContractRepository(self.repository_root)
        contract_repository.load()
        self.assertEqual(
            [],
            contract_repository.validate_instance(
                "guest-installed-runtime-evidence.schema.json",
                reboot_document,
            ),
        )

    def test_identity_change_after_reboot_is_failed_without_partial_identity(
        self,
    ) -> None:
        changed = copy.deepcopy(self.identity)
        changed["bootstrap"]["privateMaterialSet"]["sha256"] = "b" * 64
        workflow = runner.Runner(self.journal)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-a", "boot-a", "boot-b", "boot-b"],
                [self.identity, changed],
            ),
        ):
            workflow.record_first_boot()
        self.record_verified_direct_upload(workflow)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-b", "boot-b"],
                [changed],
            ),
        ):
            reboot = workflow.record_post_reboot()
        self.assertEqual("failed", reboot.status)
        document = self.journal.load_stage_document(runner.POST_REBOOT_STAGE)
        self.assertEqual(
            "guest-operational-state-identity-changed-after-reboot",
            document["issue"]["code"],
        )
        self.assertNotIn("identity", document)

    def test_records_direct_upload_only_after_owner_lineage_matches(
        self,
    ) -> None:
        workflow = runner.Runner(self.journal)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-a", "boot-a"],
                [self.identity],
            ),
        ):
            workflow.record_first_boot()
        record = self.record_verified_direct_upload(workflow)
        self.assertEqual("verified", record.status)
        document = self.journal.load_stage_document(
            runner.DIRECT_UPLOAD_STAGE
        )
        self.assertEqual(
            runner.sha256_file(self.source_vital_file),
            document["sourceVitalFile"]["sha256"],
        )
        self.assertEqual(
            "recorder-1",
            document["artifact"]["attribution"]["matchedRecorderId"],
        )

    def test_direct_upload_hash_mismatch_is_failed_without_artifact(
        self,
    ) -> None:
        workflow = runner.Runner(self.journal)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-a", "boot-a"],
                [self.identity],
            ),
        ):
            workflow.record_first_boot()
        assignment, page, detail = self.direct_upload_owner_documents()
        page["items"][0]["artifact"]["sha256"] = "b" * 64
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.direct_upload_command_side_effect(
                assignment,
                page,
                detail,
            ),
        ), mock.patch.object(
            runner,
            "execute_upload_command",
            return_value=self.observation(
                self.curl,
                ("upload",),
                0,
                "success",
            ),
        ):
            record = workflow.record_direct_upload(
                self.source_vital_file,
                "http://edge",
                "recorder-1",
                "OR-01",
                "VR-01",
                "c78-upload-1",
                self.curl,
            )
        self.assertEqual("failed", record.status)
        document = self.journal.load_stage_document(
            runner.DIRECT_UPLOAD_STAGE
        )
        self.assertEqual(
            "recorder-direct-upload-lineage-not-unique",
            document["issue"]["code"],
        )
        self.assertNotIn("artifact", document)

    def test_upload_command_streams_one_complete_multipart_file(self) -> None:
        inputs = runner.validate_direct_upload_inputs(
            self.source_vital_file,
            "http://edge/",
            "recorder-1",
            "OR-01",
            "VR-01",
            "c78-upload-1",
            self.curl,
        )
        expected = self.observation(self.curl, ("ignored",), 0, "success")
        with mock.patch.object(
            runner,
            "execute_command",
            return_value=expected,
        ) as execute:
            self.assertIs(expected, runner.execute_upload_command(inputs))
        arguments = execute.call_args.args[1]
        self.assertEqual(330, execute.call_args.kwargs["timeout_seconds"])
        self.assertEqual(1, arguments.count("--form"))
        self.assertIn(
            "vitalfile=@"
            + str(self.source_vital_file)
            + ";type=application/x-vital",
            arguments,
        )
        self.assertEqual("http://edge/upload", arguments[-1])
        self.assertNotIn("segment", " ".join(arguments))

    def test_unavailable_readiness_cannot_be_verified_first_boot(self) -> None:
        workflow = runner.Runner(self.journal)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-a", "boot-a"],
                [self.identity],
                readiness_state="failed",
            ),
        ):
            checkpoint = workflow.record_first_boot()
        self.assertEqual("failed", checkpoint.status)
        document = self.journal.load_stage_document(runner.FIRST_BOOT_STAGE)
        self.assertEqual(
            "guest-runtime-readiness-not-available",
            document["issue"]["code"],
        )
        self.assertNotIn("identity", document)

    def test_available_but_not_ready_value_cannot_be_verified(self) -> None:
        def execute(
            executable: Path,
            arguments: tuple[str, ...],
        ) -> runner.CommandObservation:
            if executable == self.sysctl:
                return self.observation(executable, arguments, 0, "boot-a\n")
            if arguments[-2:] == ("runtime", "readiness"):
                return self.observation(
                    executable,
                    arguments,
                    0,
                    json.dumps(
                        {
                            "httpStatus": 200,
                            "document": {
                                "schemaVersion": "v1",
                                "state": "available",
                                "observedAt": "2026-07-24T23:29:59Z",
                                "value": {
                                    "schemaVersion": "v1",
                                    "state": "starting",
                                    "observedAt": "2026-07-24T23:29:59Z",
                                },
                            },
                        }
                    ),
                )
            return self.observation(
                executable,
                arguments,
                0,
                json.dumps(
                    {
                        "httpStatus": 200,
                        "document": {
                            "schemaVersion": "v1",
                            "state": "available",
                            "observedAt": "2026-07-24T23:29:59Z",
                            "value": self.identity,
                        },
                    }
                ),
            )

        with mock.patch.object(runner, "execute_command", side_effect=execute):
            record = runner.Runner(self.journal).record_first_boot()
        self.assertEqual("failed", record.status)
        document = self.journal.load_stage_document(runner.FIRST_BOOT_STAGE)
        self.assertEqual(
            "guest-runtime-readiness-not-ready",
            document["issue"]["code"],
        )

    def test_journal_failure_does_not_leave_published_evidence(self) -> None:
        workflow = runner.Runner(self.journal)
        with mock.patch.object(
            runner,
            "execute_command",
            side_effect=self.command_side_effect(
                ["boot-a", "boot-a"],
                [self.identity],
            ),
        ), mock.patch.object(
            self.journal,
            "record",
            side_effect=runner.GuestInstalledRuntimeEvidenceError(
                "journal unavailable"
            ),
        ):
            with self.assertRaisesRegex(
                runner.GuestInstalledRuntimeEvidenceError,
                "journal unavailable",
            ):
                workflow.record_first_boot()
        self.assertFalse(
            (self.evidence_directory / "first-boot-checkpoint.json").exists()
        )


if __name__ == "__main__":
    unittest.main()
