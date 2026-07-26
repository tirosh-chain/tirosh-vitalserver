"""Executable C35 GuestArtifactCompiler boundary checks."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tooling import guest_artifact_compiler as compiler


class GuestArtifactCompilerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.input_root = self.root / "release-input"
        self.input_root.mkdir()
        self.sources = {
            "kernel": self.write_input("inputs/boot/Image", b"linux-kernel"),
            "initial_ramdisk": self.write_input("inputs/boot/initrd.img", b"linux-initrd"),
            "guest_runtime": self.write_input("inputs/services/guest-runtime", b"guest-runtime"),
            "guest_telemetry_collector": self.write_input(
                "inputs/services/guest-telemetry-collector", b"guest-telemetry-collector"
            ),
            "guest_telemetry_collector_configuration": self.write_input(
                "inputs/configuration/guest-telemetry-collector.yaml",
                b"receivers: {}\n",
            ),
            "guest_node_services": self.write_input("inputs/services/guest-node-services.tar.gz", b"guest-node-services"),
            "guest_product_process_supervisor": self.write_input("inputs/services/guest-product-process-supervisor", b"guest-product-process-supervisor"),
            "guest_product_process_deployment_configuration": self.write_input("inputs/configuration/guest-product-process-deployment.json", b"guest-product-process-deployment"),
            "guest_product_release_manager": self.write_input("inputs/services/guest-product-release-manager", b"guest-product-release-manager"),
            "guest_product_release_manager_configuration": self.write_input("inputs/configuration/guest-product-release-manager.json", b"guest-product-release-manager-configuration"),
            "guest_product_service_manager_deployment_configuration": self.write_input("inputs/configuration/guest-product-service-manager-deployment.json", b"guest-product-service-manager-deployment"),
            "guest_product_bootstrap_configuration": self.write_input("inputs/configuration/guest-product-bootstrap.json", b"guest-product-bootstrap"),
            "guest_product_vitalserver_topology_deployment": self.write_input("inputs/configuration/guest-product-vitalserver-topology-deployment.json", b"guest-product-vitalserver-topology-deployment"),
            "external_vitalserver_delivery_configuration": self.write_input("inputs/configuration/external-vitalserver-delivery-configuration.json", b"external-vitalserver-delivery-configuration"),
            "root_storage": self.write_input("inputs/storage/base-root.raw", b"linux-root-storage"),
        }
        self.builder = self.write_builder("success")
        self.command_path = self.root / "guest-artifact-compilation-command.json"
        self.write_command(self.command_document())
        self.output_directory = self.root / "compiled-guest-artifacts"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_input(self, relative_path: str, contents: bytes) -> Path:
        path = self.input_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        return path

    def write_builder(self, behavior: str) -> Path:
        path = self.root / f"guest-product-bootstrap-artifact-composer-{behavior}.py"
        path.write_text(
            "#!/usr/bin/env python3\n"
            "import argparse\n"
            "import json\n"
            "from pathlib import Path\n"
            "parser = argparse.ArgumentParser()\n"
            "parser.add_argument('--guest-artifact-compilation-command', required=True)\n"
            "parser.add_argument('--input-root', required=True)\n"
            "parser.add_argument('--output-directory', required=True)\n"
            "args = parser.parse_args()\n"
            "command = json.loads(Path(args.guest_artifact_compilation_command).read_text())\n"
            "input_root = Path(args.input_root)\n"
            "output_directory = Path(args.output_directory)\n"
            "def source(artifact): return input_root / artifact['inputRelativePath']\n"
            "def write(relative, content):\n"
            "    target = output_directory / relative\n"
            "    target.parent.mkdir(parents=True, exist_ok=True)\n"
            "    target.write_bytes(content)\n"
            "if 'boot' in command:\n"
            "    write(command['boot']['kernel']['outputRelativePath'], source(command['boot']['kernel']['source']).read_bytes())\n"
            "    if 'initialRamdisk' in command['boot']:\n"
            "        write(command['boot']['initialRamdisk']['outputRelativePath'], source(command['boot']['initialRamdisk']['source']).read_bytes())\n"
            "for storage in command['storageDevices']:\n"
            "    payload = source(storage['baseImage']).read_bytes() if 'baseImage' in storage else b'bootstrap-volume'\n"
            "    write(storage['outputRelativePath'], payload)\n"
            + ("write('undeclared-output.txt', b'not declared')\n" if behavior == "extra-output" else "")
            + ("raise SystemExit(17)\n" if behavior == "failure" else ""),
            encoding="utf-8",
        )
        path.chmod(0o755)
        return path

    @staticmethod
    def sha256(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def artifact(self, identifier: str, path: Path) -> dict[str, object]:
        return {
            "id": identifier,
            "inputRelativePath": path.relative_to(self.input_root).as_posix(),
            "sizeBytes": path.stat().st_size,
            "sha256": self.sha256(path),
        }

    def command_document(self) -> dict[str, object]:
        return {
            "schemaVersion": "v1",
            "compilationId": "guest-artifact-test-build",
            "artifactSetId": "guest-artifact-test-set",
            "architecture": "arm64",
            "buildEnvironment": {
                "id": "test-guest-product-bootstrap-artifact-composer",
                "builderExecutableSizeBytes": self.builder.stat().st_size,
                "builderExecutableSHA256": self.sha256(self.builder),
            },
            "boot": {
                "kernel": {"source": self.artifact("linux-arm64-kernel", self.sources["kernel"]), "outputRelativePath": "boot/Image"},
                "initialRamdisk": {"source": self.artifact("linux-arm64-initrd", self.sources["initial_ramdisk"]), "outputRelativePath": "boot/initrd.img"},
            },
            "guestRuntimeArtifact": self.artifact("guest-runtime-linux-arm64", self.sources["guest_runtime"]),
            "guestTelemetryCollectorArtifact": self.artifact(
                "guest-telemetry-collector-linux-arm64",
                self.sources["guest_telemetry_collector"],
            ),
            "guestTelemetryCollectorConfigurationArtifact": self.artifact(
                "guest-telemetry-collector-configuration",
                self.sources["guest_telemetry_collector_configuration"],
            ),
            "guestNodeServicesArtifact": self.artifact("guest-node-services-linux-arm64", self.sources["guest_node_services"]),
            "guestProductProcessSupervisorArtifact": self.artifact("guest-product-process-supervisor-linux-arm64", self.sources["guest_product_process_supervisor"]),
            "guestProductProcessDeploymentConfigurationArtifact": self.artifact("guest-product-process-deployment-configuration", self.sources["guest_product_process_deployment_configuration"]),
            "guestProductReleaseManagerArtifact": self.artifact("guest-product-release-manager-linux-arm64", self.sources["guest_product_release_manager"]),
            "guestProductReleaseManagerConfigurationArtifact": self.artifact("guest-product-release-manager-configuration", self.sources["guest_product_release_manager_configuration"]),
            "guestProductServiceManagerDeploymentConfigurationArtifact": self.artifact("guest-product-service-manager-deployment-configuration", self.sources["guest_product_service_manager_deployment_configuration"]),
            "guestProductBootstrapConfigurationArtifact": self.artifact("guest-product-bootstrap-configuration", self.sources["guest_product_bootstrap_configuration"]),
            "guestProductVitalServerTopologyDeploymentArtifact": self.artifact("guest-product-vitalserver-topology-deployment", self.sources["guest_product_vitalserver_topology_deployment"]),
            "externalVitalServerDeliveryConfigurationArtifact": self.artifact("external-vitalserver-delivery-configuration", self.sources["external_vitalserver_delivery_configuration"]),
            "storageDevices": [
                {
                    "id": "guest-root",
                    "role": "guest-root-storage",
                    "storageImageFormat": "raw",
                    "readOnly": False,
                    "baseImage": self.artifact("linux-arm64-root-storage-base", self.sources["root_storage"]),
                    "outputRelativePath": "storage/guest-root.raw",
                },
                {
                    "id": "guest-product-bootstrap",
                    "role": "guest-product-bootstrap-volume",
                    "storageImageFormat": "raw",
                    "guestVolumeFileSystem": "iso9660",
                    "readOnly": True,
                    "outputRelativePath": "storage/guest-product-bootstrap.raw",
                },
            ],
        }

    def write_command(self, document: dict[str, object]) -> None:
        self.command_path.write_text(json.dumps(document, sort_keys=True), encoding="utf-8")

    def amd64_command_document(self) -> dict[str, object]:
        command = json.loads(json.dumps(self.command_document()))
        command["architecture"] = "amd64"
        command["artifactSetId"] = "guest-artifact-test-set-amd64"
        del command["boot"]
        for key in (
            "guestRuntimeArtifact",
            "guestTelemetryCollectorArtifact",
            "guestNodeServicesArtifact",
            "guestProductProcessSupervisorArtifact",
            "guestProductReleaseManagerArtifact",
        ):
            command[key]["id"] = command[key]["id"].replace("linux-arm64", "linux-amd64")
        command["storageDevices"][0]["baseImage"]["id"] = "linux-amd64-root-storage-base"
        return command

    def execution(self, **changes: object) -> compiler.GuestArtifactCompilationExecution:
        values: dict[str, object] = {
            "compilation_command_path": self.command_path,
            "input_root": self.input_root,
            "builder_executable": self.builder,
            "output_directory": self.output_directory,
            "builder_timeout_seconds": 10,
        }
        values.update(changes)
        return compiler.GuestArtifactCompilationExecution(**values)

    def test_compiles_explicit_inputs_and_atomically_publishes_c34_and_c35_receipt(self) -> None:
        with mock.patch.object(
            compiler,
            "record_utc_guest_artifact_compilation_completion_time",
            return_value=datetime(2026, 7, 17, 10, 0, tzinfo=timezone.utc),
        ):
            result = compiler.compile_guest_artifact_set(self.execution())

        self.assertTrue(self.output_directory.is_dir())
        self.assertEqual(b"linux-kernel", (self.output_directory / "boot/Image").read_bytes())
        self.assertEqual(b"linux-root-storage", (self.output_directory / "storage/guest-root.raw").read_bytes())
        self.assertEqual(b"bootstrap-volume", (self.output_directory / "storage/guest-product-bootstrap.raw").read_bytes())
        manifest_path = self.output_directory / "macos-guest-artifact-manifest.json"
        receipt_path = self.output_directory / "guest-artifact-compilation-receipt.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertEqual("guest-artifact-test-set", manifest["artifactSetId"])
        self.assertEqual(self.sha256(self.command_path), receipt["compilationCommandSHA256"])
        self.assertEqual(self.sha256(manifest_path), receipt["macOSGuestArtifactManifest"]["sha256"])
        self.assertEqual("2026-07-17T10:00:00Z", receipt["completedAt"])
        self.assertEqual(result["guestArtifactCompilationReceipt"], receipt)
        self.assertFalse(list(self.root.glob(".compiled-guest-artifacts.*")))

        self.assertEqual("v1", manifest["schemaVersion"])
        self.assertEqual("v1", receipt["schemaVersion"])
        self.assertEqual("macos-guest-artifact-manifest.json", receipt["macOSGuestArtifactManifest"]["relativePath"])
        self.assertIn(
            "external-vitalserver-delivery-configuration",
            {artifact["id"] for artifact in receipt["consumedInputArtifacts"]},
        )
        self.assertEqual(
            {
                "guest-telemetry-collector-linux-arm64",
                "guest-telemetry-collector-configuration",
            },
            {
                artifact["id"]
                for artifact in receipt["consumedInputArtifacts"]
                if artifact["id"].startswith("guest-telemetry-collector")
            },
        )

    def test_rejects_partial_guest_telemetry_collector_declaration_before_builder_effect(
        self,
    ) -> None:
        command = self.command_document()
        del command["guestTelemetryCollectorConfigurationArtifact"]
        self.write_command(command)

        with self.assertRaisesRegex(
            compiler.GuestArtifactCompilationError,
            "stage=command-validate.*Collector binary and configuration",
        ):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_compiles_amd64_native_guest_disk_and_bootstrap_volume_without_macos_boot_outputs(self) -> None:
        self.write_command(self.amd64_command_document())
        with mock.patch.object(
            compiler,
            "record_utc_guest_artifact_compilation_completion_time",
            return_value=datetime(2026, 7, 17, 10, 0, tzinfo=timezone.utc),
        ):
            result = compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse((self.output_directory / "boot").exists())
        manifest_path = self.output_directory / "native-guest-artifact-manifest.json"
        receipt_path = self.output_directory / "guest-artifact-compilation-receipt.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertEqual("amd64", manifest["architecture"])
        self.assertEqual("guest-artifact-test-set-amd64", manifest["artifactSetId"])
        self.assertEqual("amd64", receipt["architecture"])
        self.assertEqual(self.sha256(manifest_path), receipt["nativeGuestArtifactManifest"]["sha256"])
        self.assertEqual(manifest, result["nativeGuestArtifactManifest"])

    def test_rejects_amd64_command_that_claims_macos_boot_outputs(self) -> None:
        command = self.amd64_command_document()
        command["boot"] = self.command_document()["boot"]
        self.write_command(command)

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=command-validate.*amd64.*boot"):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_an_unowned_guest_runtime_configuration_artifact(self) -> None:
        command = self.command_document()
        configuration = self.write_input(
            "inputs/configuration/guest-runtime.json", b"guest-configuration"
        )
        command["guestRuntimeConfigurationArtifact"] = self.artifact(
            "guest-runtime-configuration", configuration
        )
        self.write_command(command)

        with self.assertRaisesRegex(
            compiler.GuestArtifactCompilationError,
            "stage=command-validate.*missing or unknown",
        ):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_input_digest_mismatch_before_builder_effect_or_output_publication(self) -> None:
        self.sources["guest_runtime"].write_bytes(b"different-guest-runtime")

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=input-identity.*guest-runtime-linux-arm64"):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_builder_identity_mismatch_before_builder_effect_or_output_publication(self) -> None:
        command = self.command_document()
        command["buildEnvironment"]["builderExecutableSHA256"] = "0" * 64
        self.write_command(command)

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=builder-identity"):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_undeclared_builder_output_and_does_not_publish_partial_artifacts(self) -> None:
        extra_builder = self.write_builder("extra-output")
        command = self.command_document()
        command["buildEnvironment"] = {
            "id": "test-guest-product-bootstrap-artifact-composer",
            "builderExecutableSizeBytes": extra_builder.stat().st_size,
            "builderExecutableSHA256": self.sha256(extra_builder),
        }
        self.write_command(command)

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=output-validate.*undeclared-output"):
            compiler.compile_guest_artifact_set(self.execution(builder_executable=extra_builder))

        self.assertFalse(self.output_directory.exists())
        self.assertFalse(list(self.root.glob(".compiled-guest-artifacts.*")))

    def test_rejects_noncanonical_storage_output_name_before_the_builder_is_invoked(self) -> None:
        command = self.command_document()
        command["storageDevices"][0]["outputRelativePath"] = "storage/guessed.raw"
        self.write_command(command)

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=command-validate.*guest-root"):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_missing_guest_product_bootstrap_configuration_before_builder_effect(self) -> None:
        command = self.command_document()
        del command["guestProductBootstrapConfigurationArtifact"]
        self.write_command(command)

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=command-validate.*missing or unknown"):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_missing_guest_product_vitalserver_topology_deployment_before_builder_effect(self) -> None:
        command = self.command_document()
        del command["guestProductVitalServerTopologyDeploymentArtifact"]
        self.write_command(command)

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=command-validate.*missing or unknown"):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_a_guest_product_release_manager_with_an_unowned_identity(self) -> None:
        command = self.command_document()
        command["guestProductReleaseManagerArtifact"]["id"] = "guessed-release-manager"
        self.write_command(command)

        with self.assertRaisesRegex(
            compiler.GuestArtifactCompilationError,
            "stage=command-validate.*guestProductReleaseManagerArtifact ID",
        ):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_rejects_bootstrap_storage_that_names_a_base_image(self) -> None:
        command = self.command_document()
        command["storageDevices"][1]["baseImage"] = command["storageDevices"][0]["baseImage"]
        self.write_command(command)

        with self.assertRaisesRegex(compiler.GuestArtifactCompilationError, "stage=command-validate"):
            compiler.compile_guest_artifact_set(self.execution())

        self.assertFalse(self.output_directory.exists())

    def test_execution_does_not_accept_a_caller_supplied_completion_time(self) -> None:
        """C35 records its own completion time after the selected builder succeeds."""

        with self.assertRaises(TypeError):
            self.execution(completed_at=datetime(2026, 7, 17, 10, 0))

    def test_cli_rejects_a_caller_supplied_completion_time(self) -> None:
        with self.assertRaises(SystemExit):
            compiler.parse_arguments(
                [
                    "--compilation-command", str(self.command_path),
                    "--input-root", str(self.input_root),
                    "--builder-executable", str(self.builder),
                    "--output-directory", str(self.output_directory),
                    "--builder-timeout-seconds", "10",
                    "--completed-at", "2026-07-17T10:00:00",
                ]
            )


if __name__ == "__main__":
    unittest.main()
