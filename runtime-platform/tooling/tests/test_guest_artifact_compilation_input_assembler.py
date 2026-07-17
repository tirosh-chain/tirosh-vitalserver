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
            "recorder-gateway-linux-arm64": b"recorder-gateway-archive",
            "guest-product-process-supervisor-linux-arm64": b"guest-product-process-supervisor",
            "guest-product-process-deployment-configuration": b'{"schemaVersion":"v1"}',
            "guest-product-service-manager-deployment-configuration": b'{"schemaVersion":"v1"}',
            "guest-product-bootstrap-configuration": b'{"schemaVersion":"v1"}',
            "guest-product-vitalserver-topology-deployment": b'{"schemaVersion":"v1"}',
            "external-vitalserver-delivery-configuration": b'{"schemaVersion":"v1"}',
            "linux-arm64-root-storage-base": b"linux-root-storage",
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
        self.assertEqual(11, len(receipt["assembledInputArtifacts"]))
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
