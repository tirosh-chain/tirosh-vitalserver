"""C41 release input assembly boundary checks."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tooling import guest_artifact_compilation_input_assembler as assembler
from tooling import guest_artifact_compiler


class GuestArtifactCompilationInputAssemblerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.release_sources = self.root / "release-sources"
        self.release_sources.mkdir()
        self.source_paths = self.write_declared_sources()
        self.declaration_path = self.root / "guest-artifact-compilation-input-assembly-declaration.json"
        self.write_declaration()
        self.assembled_input_root = self.root / "assembled-c35-input"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_declared_sources(self) -> dict[str, Path]:
        contents_by_id = {
            "guest-product-bootstrap-artifact-composer": b"guest-product-bootstrap-artifact-composer",
            "linux-arm64-kernel": b"linux-kernel",
            "linux-arm64-initrd": b"linux-initrd",
            "guest-runtime-linux-arm64": b"guest-runtime",
            "guest-telemetry-collector-linux-arm64": b"guest-telemetry-collector",
            "guest-telemetry-collector-configuration": b"receivers: {}\n",
            "guest-node-services-linux-arm64": b"guest-node-services-archive",
            "guest-product-process-supervisor-linux-arm64": b"guest-product-process-supervisor",
            "guest-product-process-deployment-configuration": b'{"schemaVersion":"v1"}',
            "guest-product-release-manager-linux-arm64": b"guest-product-release-manager",
            "guest-product-release-manager-configuration": b'{"schemaVersion":"v1"}',
            "guest-product-service-manager-deployment-configuration": b'{"schemaVersion":"v1"}',
            "guest-product-bootstrap-configuration": b'{"schemaVersion":"v1"}',
            "guest-product-vitalserver-topology-deployment": b'{"schemaVersion":"v1"}',
            "external-vitalserver-delivery-configuration": b'{"schemaVersion":"v1"}',
            "linux-arm64-root-storage-base": b"linux-root-storage",
            "guest-runtime-linux-amd64": b"guest-runtime",
            "guest-telemetry-collector-linux-amd64": b"guest-telemetry-collector",
            "guest-node-services-linux-amd64": b"guest-node-services-archive",
            "guest-product-process-supervisor-linux-amd64": b"guest-product-process-supervisor",
            "guest-product-release-manager-linux-amd64": b"guest-product-release-manager",
            "linux-amd64-root-storage-base": b"linux-root-storage",
        }
        result: dict[str, Path] = {}
        for identifier, contents in contents_by_id.items():
            path = self.release_sources / identifier
            path.write_bytes(contents)
            if identifier in {
                "guest-product-bootstrap-artifact-composer",
            }:
                path.chmod(0o755)
            result[identifier] = path
        return result

    def write_declaration(self) -> None:
        fixture = (
            Path(__file__).resolve().parents[2]
            / "contracts/examples/v1/valid/guest-artifact-compilation-input-assembly-declaration.json"
        )
        document = json.loads(fixture.read_text(encoding="utf-8"))

        def replace_sources(value: object) -> None:
            if isinstance(value, dict):
                identifier = value.get("id")
                if isinstance(identifier, str) and "sourceAbsolutePath" in value:
                    value["sourceAbsolutePath"] = str(self.source_paths[identifier])
                for child in value.values():
                    replace_sources(child)
            elif isinstance(value, list):
                for child in value:
                    replace_sources(child)

        replace_sources(document)
        self.declaration_path.write_text(json.dumps(document), encoding="utf-8")

    def execution(self, **changes: object) -> assembler.GuestArtifactCompilationInputAssemblyExecution:
        values: dict[str, object] = {
            "assembly_declaration_path": self.declaration_path,
            "assembled_input_root": self.assembled_input_root,
        }
        values.update(changes)
        return assembler.GuestArtifactCompilationInputAssemblyExecution(**values)

    def test_assembles_complete_c35_input_root_without_publishing_build_machine_paths(self) -> None:
        with mock.patch.object(
            assembler,
            "record_utc_input_assembly_completion_time",
            return_value=datetime(2026, 7, 17, 12, 0, tzinfo=timezone.utc),
        ):
            result = assembler.assemble_guest_artifact_compilation_input(
                self.execution()
            )

        self.assertEqual(str(self.assembled_input_root), result["assembledInputRoot"])
        command_path = self.assembled_input_root / "guest-artifact-compilation-command.json"
        command = guest_artifact_compiler.parse_guest_artifact_compilation_command(
            command_path.read_bytes()
        )
        self.assertEqual("guest-artifact-build-0.1.0-dev", command.compilation_id)
        self.assertEqual("vitalserver-guest-arm64-0.1.0-dev", command.artifact_set_id)
        self.assertEqual(
            b'{"schemaVersion":"v1"}',
            (self.assembled_input_root / "inputs/configuration/guest-product-bootstrap.json").read_bytes(),
        )
        self.assertEqual(
            b'{"schemaVersion":"v1"}',
            (self.assembled_input_root / "inputs/configuration/guest-product-vitalserver-topology-deployment.json").read_bytes(),
        )
        self.assertEqual(
            b'{"schemaVersion":"v1"}',
            (self.assembled_input_root / "inputs/configuration/external-vitalserver-delivery-configuration.json").read_bytes(),
        )
        self.assertIsNotNone(command.external_vitalserver_delivery_configuration_artifact)
        self.assertEqual(
            "external-vitalserver-delivery-configuration",
            command.external_vitalserver_delivery_configuration_artifact.identifier,
        )
        self.assertTrue(
            (self.assembled_input_root / "builders/guest-product-bootstrap-artifact-composer").stat().st_mode & 0o111
        )
        receipt_path = self.assembled_input_root / "guest-artifact-compilation-input-assembly-receipt.json"
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertEqual("2026-07-17T12:00:00Z", receipt["completedAt"])
        self.assertEqual(13, len(receipt["assembledInputArtifacts"]))
        self.assertNotIn(str(self.release_sources), command_path.read_text(encoding="utf-8"))
        self.assertNotIn(str(self.release_sources), receipt_path.read_text(encoding="utf-8"))

    def test_cli_rejects_a_caller_supplied_completion_time(self) -> None:
        """The C41 effect owns its receipt time; the caller cannot provide it."""

        with self.assertRaises(SystemExit):
            assembler.parse_arguments(
                [
                    "--assembly-declaration",
                    str(self.declaration_path),
                    "--assembled-input-root",
                    str(self.assembled_input_root),
                    "--completed-at",
                    "2026-07-17T12:00:00Z",
                ]
            )

    def test_assembles_declared_guest_telemetry_collector_pair_into_c35(self) -> None:
        document = json.loads(self.declaration_path.read_text(encoding="utf-8"))
        document["guestTelemetryCollectorArtifact"] = {
            "id": "guest-telemetry-collector-linux-arm64",
            "sourceAbsolutePath": str(
                self.source_paths["guest-telemetry-collector-linux-arm64"]
            ),
            "inputRelativePath": "inputs/services/guest-telemetry-collector",
        }
        document["guestTelemetryCollectorConfigurationArtifact"] = {
            "id": "guest-telemetry-collector-configuration",
            "sourceAbsolutePath": str(
                self.source_paths["guest-telemetry-collector-configuration"]
            ),
            "inputRelativePath": "inputs/configuration/guest-telemetry-collector.yaml",
        }
        self.declaration_path.write_text(json.dumps(document), encoding="utf-8")

        assembler.assemble_guest_artifact_compilation_input(self.execution())

        command = guest_artifact_compiler.parse_guest_artifact_compilation_command(
            (self.assembled_input_root / "guest-artifact-compilation-command.json").read_bytes()
        )
        self.assertEqual(
            "guest-telemetry-collector-linux-arm64",
            command.guest_telemetry_collector_artifact.identifier,
        )
        self.assertEqual(
            "guest-telemetry-collector-configuration",
            command.guest_telemetry_collector_configuration_artifact.identifier,
        )
        self.assertEqual(
            b"guest-telemetry-collector",
            (
                self.assembled_input_root
                / "inputs/services/guest-telemetry-collector"
            ).read_bytes(),
        )

    def test_assembles_amd64_c35_input_without_macos_boot_sources(self) -> None:
        document = json.loads(self.declaration_path.read_text(encoding="utf-8"))
        document["architecture"] = "amd64"
        document["artifactSetId"] = "vitalserver-guest-amd64-0.1.0-dev"
        del document["boot"]

        def replace_architecture_source(value: object) -> None:
            if isinstance(value, dict):
                identifier = value.get("id")
                if isinstance(identifier, str) and "linux-arm64" in identifier:
                    updated = identifier.replace("linux-arm64", "linux-amd64")
                    value["id"] = updated
                    if "sourceAbsolutePath" in value:
                        value["sourceAbsolutePath"] = str(self.source_paths[updated])
                for child in value.values():
                    replace_architecture_source(child)
            elif isinstance(value, list):
                for child in value:
                    replace_architecture_source(child)

        replace_architecture_source(document)
        self.declaration_path.write_text(json.dumps(document), encoding="utf-8")

        assembler.assemble_guest_artifact_compilation_input(self.execution())

        command = guest_artifact_compiler.parse_guest_artifact_compilation_command(
            (self.assembled_input_root / "guest-artifact-compilation-command.json").read_bytes()
        )
        self.assertEqual("amd64", command.architecture)
        self.assertIsNone(command.kernel)
        self.assertIsNone(command.initial_ramdisk)
        self.assertEqual("guest-runtime-linux-amd64", command.guest_runtime_artifact.identifier)
        self.assertFalse((self.assembled_input_root / "inputs/boot").exists())

    def test_rejects_symlinked_bootstrap_configuration_source_without_publishing_input_root(self) -> None:
        configuration = self.source_paths["guest-product-bootstrap-configuration"]
        configuration.unlink()
        configuration.symlink_to(self.source_paths["guest-product-bootstrap-artifact-composer"])

        with self.assertRaisesRegex(
            assembler.GuestArtifactCompilationInputAssemblyError,
            "stage=source-validate.*guest-product-bootstrap-configuration.*non-symlink",
        ):
            assembler.assemble_guest_artifact_compilation_input(self.execution())

        self.assertFalse(self.assembled_input_root.exists())

    def test_rejects_non_executable_builder_source_without_publishing_input_root(self) -> None:
        self.source_paths["guest-product-bootstrap-artifact-composer"].chmod(0o644)

        with self.assertRaisesRegex(
            assembler.GuestArtifactCompilationInputAssemblyError,
            "stage=source-validate.*GuestProductBootstrapArtifactComposer source is not executable",
        ):
            assembler.assemble_guest_artifact_compilation_input(self.execution())

        self.assertFalse(self.assembled_input_root.exists())


if __name__ == "__main__":
    unittest.main()
