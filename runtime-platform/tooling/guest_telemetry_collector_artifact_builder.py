"""Build one explicit Linux Guest OpenTelemetry Collector artifact.

This release-build adapter owns only the deterministic effect of turning the
selected Collector-builder configuration into one declared Linux executable.  It
does not select a remote telemetry backend, alter Guest deployment intent, or
infer an output location.  C35/C39 later identify and install the resulting
bytes explicitly.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Sequence


MAXIMUM_CONFIGURATION_BYTES = 1 << 20
_OTELCOL_VERSION_PATTERN = re.compile(
    r"(?m)^\s*otelcol_version:\s*[\"']?(?P<version>\d+\.\d+\.\d+)[\"']?\s*$"
)
_DIST_NAME_PATTERN = re.compile(
    r"(?m)^\s*name:\s*[\"']?(?P<name>[A-Za-z0-9][A-Za-z0-9._-]*)[\"']?\s*$"
)
_OUTPUT_PATH_PATTERN = re.compile(r"(?m)^(?P<prefix>\s*output_path:\s*).*$", re.ASCII)


class GuestTelemetryCollectorArtifactBuildError(RuntimeError):
    """The selected Collector configuration could not produce a Guest binary."""


@dataclass(frozen=True)
class GuestTelemetryCollectorArtifactBuildExecution:
    """All caller-selected build inputs and the single output destination."""

    builder_configuration: Path
    collector_configuration: Path
    output_artifact: Path
    go_executable: str
    go_toolchain: str
    guest_architecture: str


@dataclass(frozen=True)
class GuestTelemetryCollectorBuilderConfiguration:
    """The small identity subset this adapter needs from the selected OCB file."""

    otelcol_version: str
    distribution_name: str
    contents: str


def build_guest_telemetry_collector_artifact(
    execution: GuestTelemetryCollectorArtifactBuildExecution,
) -> dict[str, str]:
    """Build and atomically publish the declared Linux Guest Collector binary."""

    configuration = read_builder_configuration(execution.builder_configuration)
    validate_execution(execution)
    with tempfile.TemporaryDirectory(
        prefix=f".{execution.output_artifact.name}.collector-build.",
        dir=execution.output_artifact.parent,
    ) as temporary_directory_name:
        temporary_directory = Path(temporary_directory_name)
        builder_module_directory = temporary_directory / "builder-module"
        builder_module_directory.mkdir(mode=0o700)
        build_configuration_path = temporary_directory / "collector-builder.yaml"
        collector_output_directory = temporary_directory / "collector-output"
        write_builder_module(
            builder_module_directory,
            configuration.otelcol_version,
        )
        write_selected_builder_configuration(
            build_configuration_path,
            configuration.contents,
            collector_output_directory,
        )
        builder_executable = temporary_directory / "otelcol-builder"
        build_ocb_host_executable(
            execution,
            configuration.otelcol_version,
            builder_module_directory,
            builder_executable,
        )
        run_ocb_for_linux_guest(
            execution,
            builder_executable,
            build_configuration_path,
        )
        validate_collector_runtime_configuration(
            execution,
            collector_output_directory,
        )
        generated_artifact = collector_output_directory / configuration.distribution_name
        verify_linux_elf(generated_artifact, execution.guest_architecture)
        publish_new_artifact(generated_artifact, execution.output_artifact)

    return {
        "artifactPath": str(execution.output_artifact),
        "architecture": "linux-" + execution.guest_architecture,
        "collectorVersion": configuration.otelcol_version,
    }


def read_builder_configuration(path: Path) -> GuestTelemetryCollectorBuilderConfiguration:
    """Read one bounded OCB configuration without treating absence as a build."""

    if not path.is_absolute():
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector builder configuration path must be absolute"
        )
    require_regular_non_symlink_file(path, "Collector builder configuration")
    try:
        contents = path.read_text(encoding="utf-8")
    except OSError as error:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Could not read Collector builder configuration: " + str(error)
        ) from error
    if len(contents.encode("utf-8")) > MAXIMUM_CONFIGURATION_BYTES:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector builder configuration exceeds the maximum size"
        )
    version_match = _OTELCOL_VERSION_PATTERN.search(contents)
    if version_match is None:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector builder configuration must declare one otelcol_version"
        )
    name_match = _DIST_NAME_PATTERN.search(contents)
    if name_match is None:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector builder configuration must declare one distribution name"
        )
    if len(_OUTPUT_PATH_PATTERN.findall(contents)) != 1:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector builder configuration must declare exactly one output_path"
        )
    return GuestTelemetryCollectorBuilderConfiguration(
        otelcol_version=version_match.group("version"),
        distribution_name=name_match.group("name"),
        contents=contents,
    )


def validate_execution(execution: GuestTelemetryCollectorArtifactBuildExecution) -> None:
    """Reject undeclared paths and malformed tool selection before effects."""

    if not execution.output_artifact.is_absolute():
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector output artifact path must be absolute"
        )
    if execution.output_artifact.exists() or execution.output_artifact.is_symlink():
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector output artifact already exists"
        )
    if not execution.output_artifact.parent.is_dir() or execution.output_artifact.parent.is_symlink():
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector output artifact parent must be an existing non-symlink directory"
        )
    if not execution.collector_configuration.is_absolute():
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector runtime configuration path must be absolute"
        )
    require_regular_non_symlink_file(
        execution.collector_configuration,
        "Collector runtime configuration",
    )
    if not execution.go_executable:
        raise GuestTelemetryCollectorArtifactBuildError("Go executable must be explicit")
    if not execution.go_toolchain:
        raise GuestTelemetryCollectorArtifactBuildError("Go toolchain must be explicit")
    if execution.guest_architecture not in {"arm64", "amd64"}:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Guest Collector architecture must be arm64 or amd64"
        )
    if shutil.which(execution.go_executable) is None:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Selected Go executable is unavailable: " + execution.go_executable
        )


def write_builder_module(directory: Path, collector_version: str) -> None:
    """Write an isolated Host-builder module; it is never a Guest payload."""

    module_contents = (
        "module vitalserver-guest-telemetry-collector-build\n\n"
        "go 1.25.0\n\n"
        "require go.opentelemetry.io/collector/cmd/builder v"
        + collector_version
        + "\n"
    )
    (directory / "go.mod").write_text(module_contents, encoding="utf-8")


def write_selected_builder_configuration(
    path: Path,
    source_contents: str,
    output_directory: Path,
) -> None:
    """Preserve selected OCB components while replacing only its build output."""

    contents, replacement_count = _OUTPUT_PATH_PATTERN.subn(
        lambda match: match.group("prefix") + '"' + str(output_directory) + '"',
        source_contents,
    )
    if replacement_count != 1:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector builder configuration output_path replacement failed"
        )
    path.write_text(contents, encoding="utf-8")


def build_ocb_host_executable(
    execution: GuestTelemetryCollectorArtifactBuildExecution,
    collector_version: str,
    module_directory: Path,
    output: Path,
) -> None:
    """Build OCB for the current Host; target variables must not leak here."""

    run_checked(
        [
            execution.go_executable,
            "get",
            "go.opentelemetry.io/collector/cmd/builder@v" + collector_version,
        ],
        module_directory,
        {"GOTOOLCHAIN": execution.go_toolchain},
        "OpenTelemetry Collector builder dependency selection",
    )
    run_checked(
        [
            execution.go_executable,
            "build",
            "-o",
            str(output),
            "go.opentelemetry.io/collector/cmd/builder",
        ],
        module_directory,
        {"GOTOOLCHAIN": execution.go_toolchain},
        "OpenTelemetry Collector builder host compilation",
    )
    require_regular_non_symlink_file(output, "OpenTelemetry Collector builder executable")


def run_ocb_for_linux_guest(
    execution: GuestTelemetryCollectorArtifactBuildExecution,
    builder_executable: Path,
    configuration_path: Path,
) -> None:
    """Run the Host OCB with the explicit Linux Guest architecture."""

    resolved_go = shutil.which(execution.go_executable)
    if resolved_go is None:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Selected Go executable is unavailable: " + execution.go_executable
        )
    run_checked(
        [str(builder_executable), "--config", str(configuration_path)],
        configuration_path.parent,
        {
            "GOTOOLCHAIN": execution.go_toolchain,
            "GOOS": "linux",
            "GOARCH": execution.guest_architecture,
            "CGO_ENABLED": "0",
            "PATH": str(Path(resolved_go).parent)
            + os.pathsep
            + os.environ.get("PATH", ""),
        },
        "OpenTelemetry Collector Linux "
        + execution.guest_architecture
        + " compilation",
    )


def validate_collector_runtime_configuration(
    execution: GuestTelemetryCollectorArtifactBuildExecution,
    generated_collector_directory: Path,
) -> None:
    """Validate the actual Guest configuration with a Host-built twin binary.

    The delivered executable remains the declared Linux Guest architecture. A temporary Host executable
    is only a release-build verifier, so an invalid Collector configuration
    cannot be hidden behind cross-compilation.
    """

    validator = generated_collector_directory / "guest-telemetry-collector-validator"
    run_checked(
        [execution.go_executable, "build", "-o", str(validator), "."],
        generated_collector_directory,
        {"GOTOOLCHAIN": execution.go_toolchain},
        "OpenTelemetry Collector configuration validator compilation",
    )
    require_regular_non_symlink_file(
        validator,
        "OpenTelemetry Collector configuration validator",
    )
    run_checked(
        [str(validator), "validate", "--config", str(execution.collector_configuration)],
        generated_collector_directory,
        {},
        "Guest OpenTelemetry Collector runtime configuration validation",
    )


def run_checked(
    command: Sequence[str],
    directory: Path,
    environment_updates: dict[str, str],
    operation: str,
) -> None:
    """Run one bounded external compiler effect with contextual diagnostics."""

    environment = os.environ.copy()
    environment.update(environment_updates)
    try:
        completed = subprocess.run(
            command,
            cwd=directory,
            env=environment,
            capture_output=True,
            check=False,
            text=True,
        )
    except OSError as error:
        raise GuestTelemetryCollectorArtifactBuildError(
            operation + " could not start: " + str(error)
        ) from error
    if completed.returncode != 0:
        raise GuestTelemetryCollectorArtifactBuildError(
            operation
            + " failed exit="
            + str(completed.returncode)
            + " stdout="
            + bounded_diagnostic(completed.stdout)
            + " stderr="
            + bounded_diagnostic(completed.stderr)
        )


def verify_linux_elf(path: Path, guest_architecture: str) -> None:
    """Prove the candidate is a regular ELF64 for the declared Guest CPU."""

    expected_machine_by_architecture = {"arm64": 183, "amd64": 62}
    architecture_label = {"arm64": "ARM64", "amd64": "AMD64"}
    if guest_architecture not in expected_machine_by_architecture:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Guest telemetry Collector architecture must be arm64 or amd64"
        )

    require_regular_non_symlink_file(path, "Guest telemetry Collector artifact")
    try:
        header = path.read_bytes()[:20]
    except OSError as error:
        raise GuestTelemetryCollectorArtifactBuildError(
            "Could not inspect Guest telemetry Collector artifact: " + str(error)
        ) from error
    if (
        len(header) < 20
        or header[0:4] != b"\x7fELF"
        or header[4] != 2
        or header[5] != 1
        or int.from_bytes(header[18:20], byteorder="little")
        != expected_machine_by_architecture[guest_architecture]
    ):
        raise GuestTelemetryCollectorArtifactBuildError(
            "Guest telemetry Collector artifact is not Linux "
            + architecture_label[guest_architecture]
            + " ELF"
        )


def verify_linux_arm64_elf(path: Path) -> None:
    """Compatibility helper for focused arm64 tests and the arm64 preset."""

    verify_linux_elf(path, "arm64")


def publish_new_artifact(source: Path, destination: Path) -> None:
    """Move the fully verified result into the caller-selected empty destination."""

    if destination.exists() or destination.is_symlink():
        raise GuestTelemetryCollectorArtifactBuildError(
            "Collector output artifact already exists before publication"
        )
    source.replace(destination)


def require_regular_non_symlink_file(path: Path, role: str) -> None:
    try:
        path.lstat()
    except OSError as error:
        raise GuestTelemetryCollectorArtifactBuildError(
            role + " is missing: " + str(error)
        ) from error
    if path.is_symlink() or not path.is_file():
        raise GuestTelemetryCollectorArtifactBuildError(
            role + " must be a regular non-symlink file"
        )


def bounded_diagnostic(value: str | None) -> str:
    """Retain enough compiler evidence without turning output into state."""

    if not value:
        return ""
    normalized = " ".join(value.split())
    return normalized[:4096]


def parse_arguments(arguments: Sequence[str] | None = None) -> GuestTelemetryCollectorArtifactBuildExecution:
    parser = argparse.ArgumentParser(
        description="Build one explicit Linux arm64 or amd64 Guest OpenTelemetry Collector artifact"
    )
    parser.add_argument(
        "--builder-configuration",
        required=True,
        help="required absolute OCB configuration path",
    )
    parser.add_argument(
        "--output-artifact",
        required=True,
        help="required absolute new Linux Guest Collector executable path",
    )
    parser.add_argument(
        "--collector-configuration",
        required=True,
        help="required absolute Guest Collector runtime configuration path",
    )
    parser.add_argument(
        "--go-executable",
        required=True,
        help="required Go executable selected by the release build",
    )
    parser.add_argument(
        "--go-toolchain",
        required=True,
        help="required Go toolchain selector, for example go1.25.7+auto",
    )
    parser.add_argument(
        "--guest-architecture",
        choices=("arm64", "amd64"),
        required=True,
        help="required Linux Guest architecture",
    )
    parsed = parser.parse_args(arguments)
    return GuestTelemetryCollectorArtifactBuildExecution(
        builder_configuration=Path(parsed.builder_configuration),
        collector_configuration=Path(parsed.collector_configuration),
        output_artifact=Path(parsed.output_artifact),
        go_executable=parsed.go_executable,
        go_toolchain=parsed.go_toolchain,
        guest_architecture=parsed.guest_architecture,
    )


def main(arguments: Sequence[str] | None = None) -> int:
    try:
        result = build_guest_telemetry_collector_artifact(parse_arguments(arguments))
    except GuestTelemetryCollectorArtifactBuildError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(result["artifactPath"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
