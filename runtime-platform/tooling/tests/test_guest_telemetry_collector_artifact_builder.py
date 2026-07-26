"""Boundary tests for the explicit Guest Collector release-build adapter."""

from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from tooling import guest_telemetry_collector_artifact_builder as builder


class GuestTelemetryCollectorArtifactBuilderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.configuration = self.root / "guest-telemetry-collector-builder.yaml"
        self.configuration.write_text(
            """dist:
  name: guest-telemetry-collector
  output_path: ./guest-telemetry-collector-build
  otelcol_version: 0.156.0
receivers: []
""",
            encoding="utf-8",
        )
        self.collector_configuration = self.root / "guest-telemetry-collector.yaml"
        self.collector_configuration.write_text(
            "service:\n  pipelines: {}\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_reads_the_selected_collector_builder_identity(self) -> None:
        configuration = builder.read_builder_configuration(self.configuration)

        self.assertEqual("0.156.0", configuration.otelcol_version)
        self.assertEqual("guest-telemetry-collector", configuration.distribution_name)

    def test_rewrites_only_the_selected_builder_output_location(self) -> None:
        rewritten = self.root / "rewritten.yaml"
        output_directory = self.root / "output"

        builder.write_selected_builder_configuration(
            rewritten,
            self.configuration.read_text(encoding="utf-8"),
            output_directory,
        )

        contents = rewritten.read_text(encoding="utf-8")
        self.assertIn('  output_path: "' + str(output_directory) + '"', contents)
        self.assertIn("otelcol_version: 0.156.0", contents)
        self.assertNotIn("./guest-telemetry-collector-build", contents)

    def test_rejects_a_builder_configuration_without_one_output_path(self) -> None:
        self.configuration.write_text(
            """dist:
  name: guest-telemetry-collector
  otelcol_version: 0.156.0
""",
            encoding="utf-8",
        )

        with self.assertRaisesRegex(
            builder.GuestTelemetryCollectorArtifactBuildError,
            "exactly one output_path",
        ):
            builder.read_builder_configuration(self.configuration)

    def test_accepts_only_linux_arm64_elf_artifacts(self) -> None:
        artifact = self.root / "guest-telemetry-collector"
        artifact.write_bytes(
            b"\x7fELF" + bytes((2, 1)) + b"\x00" * 12 + (183).to_bytes(2, "little")
        )

        builder.verify_linux_arm64_elf(artifact)

        artifact.write_bytes(b"not-an-elf")
        with self.assertRaisesRegex(
            builder.GuestTelemetryCollectorArtifactBuildError,
            "not Linux ARM64 ELF",
        ):
            builder.verify_linux_arm64_elf(artifact)

    def test_accepts_linux_amd64_elf_only_when_amd64_is_selected(self) -> None:
        artifact = self.root / "guest-telemetry-collector-amd64"
        artifact.write_bytes(
            b"\x7fELF" + bytes((2, 1)) + b"\x00" * 12 + (62).to_bytes(2, "little")
        )

        builder.verify_linux_elf(artifact, "amd64")

        with self.assertRaisesRegex(
            builder.GuestTelemetryCollectorArtifactBuildError,
            "not Linux ARM64 ELF",
        ):
            builder.verify_linux_elf(artifact, "arm64")

    def test_rejects_an_existing_output_before_any_build_effect(self) -> None:
        output = self.root / "existing-collector"
        output.write_bytes(b"old")
        execution = builder.GuestTelemetryCollectorArtifactBuildExecution(
            builder_configuration=self.configuration,
            collector_configuration=self.collector_configuration,
            output_artifact=output,
            go_executable="go",
            go_toolchain="go1.25.7+auto",
            guest_architecture="arm64",
        )

        with self.assertRaisesRegex(
            builder.GuestTelemetryCollectorArtifactBuildError,
            "already exists",
        ):
            builder.validate_execution(execution)


if __name__ == "__main__":
    unittest.main()
