"""Compose one explicit systemd unit for the Guest Product process supervisor.

This release-build adapter reads C38 GuestProductServiceManagerDeploymentConfiguration
and writes one new systemd unit file. It does not install, enable, start, stop,
or observe systemd. Those are Guest OS facts owned by systemd and later clean-host
or Guest smoke evidence, not by this source-to-unit transformation.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Any, Mapping, Sequence

from tooling.contracts import ContractRepository, ContractToolError


class GuestProductSystemdServiceUnitCompositionError(RuntimeError):
    """A C38 input cannot produce one explicit Guest Product systemd unit."""


def compose_guest_product_systemd_service_unit(
    deployment_configuration_path: Path,
    unit_output_path: Path,
) -> Mapping[str, str]:
    """Validate C38 and atomically write the declared systemd unit once."""

    deployment = load_guest_product_service_manager_deployment_configuration(
        deployment_configuration_path
    )
    service_unit_name = require_c38_string(deployment, "serviceUnitName", "C38")
    validate_guest_product_systemd_unit_output_path(unit_output_path, service_unit_name)
    unit_contents = render_guest_product_systemd_service_unit(deployment)
    write_new_guest_product_systemd_unit_file(unit_output_path, unit_contents)
    return {
        "serviceUnitName": service_unit_name,
        "unitOutputPath": str(unit_output_path),
    }


def load_guest_product_service_manager_deployment_configuration(
    deployment_configuration_path: Path,
) -> Mapping[str, Any]:
    """Read exactly one C38 document and reject any unavailable contract input."""

    if not deployment_configuration_path.is_absolute() or not deployment_configuration_path.is_file():
        raise GuestProductSystemdServiceUnitCompositionError(
            "C38 deployment configuration is missing or not an absolute file"
        )
    try:
        document = json.loads(deployment_configuration_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestProductSystemdServiceUnitCompositionError(
            "C38 deployment configuration cannot be read as JSON"
        ) from error
    if not isinstance(document, dict):
        raise GuestProductSystemdServiceUnitCompositionError(
            "C38 deployment configuration must be a JSON object"
        )
    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        validation_errors = repository.validate_instance(
            "guest-product-service-manager-deployment-configuration.schema.json",
            document,
        )
    except ContractToolError as error:
        raise GuestProductSystemdServiceUnitCompositionError(
            "C38 contract source is unavailable: " + str(error)
        ) from error
    if validation_errors:
        raise GuestProductSystemdServiceUnitCompositionError(
            "C38 deployment configuration is invalid: " + "; ".join(validation_errors)
        )
    return document


def render_guest_product_systemd_service_unit(deployment: Mapping[str, Any]) -> str:
    """Translate complete desired C38 input into deterministic systemd syntax."""

    if deployment.get("serviceManagerKind") != "systemd":
        raise GuestProductSystemdServiceUnitCompositionError(
            "C38 serviceManagerKind must be systemd"
        )
    supervisor = require_c38_object(deployment, "supervisor", "C38")
    restart = require_c38_object(deployment, "restart", "C38")
    logging = require_c38_object(deployment, "logging", "C38")
    install = require_c38_object(deployment, "install", "C38")
    executable_path = require_c38_string(supervisor, "executablePath", "C38 supervisor")
    deployment_configuration_path = require_c38_string(
        supervisor, "deploymentConfigurationPath", "C38 supervisor"
    )
    restart_mode = require_c38_string(restart, "mode", "C38 restart")
    restart_delay_milliseconds = restart.get("delayMilliseconds")
    if not isinstance(restart_delay_milliseconds, int) or isinstance(restart_delay_milliseconds, bool):
        raise GuestProductSystemdServiceUnitCompositionError(
            "C38 restart delayMilliseconds must be an integer"
        )
    standard_output = require_c38_string(logging, "standardOutput", "C38 logging")
    standard_error = require_c38_string(logging, "standardError", "C38 logging")
    wanted_by_target = require_c38_string(install, "wantedByTarget", "C38 install")
    return "\n".join(
        (
            "[Unit]",
            "Description=VitalServer Guest Product Process Supervisor",
            "",
            "[Service]",
            "Type=simple",
            "ExecStart=" + executable_path + " --deployment-configuration " + deployment_configuration_path,
            "Restart=" + restart_mode,
            "RestartSec=" + format_c38_restart_delay_as_systemd_seconds(restart_delay_milliseconds),
            "StandardOutput=" + standard_output,
            "StandardError=" + standard_error,
            "KillMode=control-group",
            "",
            "[Install]",
            "WantedBy=" + wanted_by_target,
            "",
        )
    )


def validate_guest_product_systemd_unit_output_path(
    unit_output_path: Path, service_unit_name: str
) -> None:
    """Reject an output that cannot be the one C38-declared unit artifact."""

    if not unit_output_path.is_absolute():
        raise GuestProductSystemdServiceUnitCompositionError(
            "systemd unit output path must be absolute"
        )
    if unit_output_path.exists():
        raise GuestProductSystemdServiceUnitCompositionError(
            "systemd unit output path already exists"
        )
    if not unit_output_path.parent.is_dir():
        raise GuestProductSystemdServiceUnitCompositionError(
            "systemd unit output parent directory is missing"
        )
    if unit_output_path.name != service_unit_name:
        raise GuestProductSystemdServiceUnitCompositionError(
            "systemd unit output name must match C38 serviceUnitName"
        )


def write_new_guest_product_systemd_unit_file(unit_output_path: Path, unit_contents: str) -> None:
    """Atomically publish the new C38-derived unit without replacing evidence."""

    descriptor, temporary_path_value = tempfile.mkstemp(
        prefix="." + unit_output_path.name + ".",
        dir=unit_output_path.parent,
        text=True,
    )
    temporary_path = Path(temporary_path_value)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as unit_file:
            unit_file.write(unit_contents)
            unit_file.flush()
            os.fsync(unit_file.fileno())
        os.replace(temporary_path, unit_output_path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise


def require_c38_object(
    document: Mapping[str, Any], field_name: str, document_name: str
) -> Mapping[str, Any]:
    """Read one required C38 object without manufacturing absent desired input."""

    value = document.get(field_name)
    if not isinstance(value, dict):
        raise GuestProductSystemdServiceUnitCompositionError(
            document_name + " requires object " + field_name
        )
    return value


def require_c38_string(document: Mapping[str, Any], field_name: str, document_name: str) -> str:
    """Read one required C38 string without treating absence as a default."""

    value = document.get(field_name)
    if not isinstance(value, str) or not value:
        raise GuestProductSystemdServiceUnitCompositionError(
            document_name + " requires non-empty " + field_name
        )
    return value


def format_c38_restart_delay_as_systemd_seconds(milliseconds: int) -> str:
    """Express the explicit C38 restart delay in systemd duration syntax."""

    seconds = milliseconds / 1000
    return format(seconds, ".3f").rstrip("0").rstrip(".") + "s"


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployment-configuration", required=True)
    parser.add_argument("--unit-output", required=True)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str]) -> int:
    parsed = parse_arguments(arguments)
    try:
        result = compose_guest_product_systemd_service_unit(
            Path(parsed.deployment_configuration),
            Path(parsed.unit_output),
        )
    except GuestProductSystemdServiceUnitCompositionError as error:
        print(
            "Guest Product systemd service unit composition failed: " + str(error),
            file=sys.stderr,
        )
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
