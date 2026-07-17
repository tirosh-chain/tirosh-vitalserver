"""Load the C23 Product Delivery declaration selected for a macOS PKG.

This module is deliberately a reader, not a package composer.  C23 belongs to
the Product Delivery bounded context and declares the release identity that a
macOS package must realize.  Package tooling consumes that explicit identity;
it must not accept a second product-version or Host service-label value that can
drift from the selected release plan.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

from tooling.contracts import ContractRepository, ContractToolError, load_json


class ProductDeliveryReleasePlanError(RuntimeError):
    """The release-process-owned C23 declaration is unavailable or incompatible."""


@dataclass(frozen=True)
class MacOSHostPackageReleasePlan:
    """The C23 facts a macOS Host PKG is required to realize.

    This is an adapter-local projection of one C23 `ReleaseDeliveryPlan`, not a
    second release document.  It makes the ownership visible where the package
    composer and verifier need product version, installer filename, installer
    receipt identifier, and both required Host launchd identities.
    """

    release_delivery_plan_id: str
    product_version: str
    expected_package_file_name: str
    macos_installer_package_identifier: str
    host_agent_launchd_service_label: str
    host_edge_proxy_launchd_service_label: str


def load_selected_macos_host_package_release_plan(
    release_delivery_plans_document_path: Path,
    release_delivery_plan_id: str,
) -> MacOSHostPackageReleasePlan:
    """Read exactly one macOS C23 plan and project its package identity.

    The document is an external, release-process-owned input.  Absence,
    malformed JSON, duplicate IDs, wrong platform, and a schema-invalid plan
    remain explicit failures instead of becoming a guessed package identity.
    """

    if not release_delivery_plans_document_path.is_absolute():
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plans document path must be absolute"
        )
    if not release_delivery_plan_id:
        raise ProductDeliveryReleasePlanError("C23 release delivery plan id is required")
    try:
        plans_document = load_json(release_delivery_plans_document_path)
    except ContractToolError as error:
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plans document cannot be read: " + str(error)
        ) from error
    plans = plans_document.get("plans")
    if plans_document.get("schemaVersion") != "v1" or not isinstance(plans, list):
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plans document requires schemaVersion v1 and plans"
        )
    selected_plans = [
        plan
        for plan in plans
        if isinstance(plan, dict) and plan.get("id") == release_delivery_plan_id
    ]
    if not selected_plans:
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plan is not declared: " + release_delivery_plan_id
        )
    if len(selected_plans) != 1:
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plan id is duplicated: " + release_delivery_plan_id
        )
    selected_plan = selected_plans[0]
    validate_c23_release_delivery_plan(selected_plan)
    return project_macos_host_package_release_plan(selected_plan)


def validate_c23_release_delivery_plan(release_delivery_plan: Mapping[str, Any]) -> None:
    """Validate one C23 plan against the canonical contract source."""

    repository = ContractRepository(Path(__file__).resolve().parents[1])
    try:
        repository.load()
        validation_errors = repository.validate_instance(
            "release-delivery-plan.schema.json",
            release_delivery_plan,
        )
    except ContractToolError as error:
        raise ProductDeliveryReleasePlanError(
            "C23 contract source is unavailable: " + str(error)
        ) from error
    if validation_errors:
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plan is invalid: " + "; ".join(validation_errors)
        )


def project_macos_host_package_release_plan(
    release_delivery_plan: Mapping[str, Any],
) -> MacOSHostPackageReleasePlan:
    """Turn a validated C23 plan into the macOS package boundary vocabulary."""

    plan_id = required_string(release_delivery_plan, "id", "C23 release delivery plan")
    if release_delivery_plan.get("platform") != "macos":
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plan must target macos for a macOS Host package"
        )
    if release_delivery_plan.get("providerKind") != "macos-virtualization":
        raise ProductDeliveryReleasePlanError(
            "C23 macOS release delivery plan must name providerKind macos-virtualization"
        )
    intended_installer_artifact = required_object(
        release_delivery_plan,
        "intendedInstallerArtifact",
        "C23 release delivery plan",
    )
    if intended_installer_artifact.get("kind") != "pkg":
        raise ProductDeliveryReleasePlanError(
            "C23 macOS intended installer artifact kind must be pkg"
        )
    expected_package_file_name = required_string(
        intended_installer_artifact,
        "expectedName",
        "C23 intended installer artifact",
    )
    if not is_plain_file_name(expected_package_file_name):
        raise ProductDeliveryReleasePlanError(
            "C23 macOS intended installer artifact expectedName must be one package file name"
        )
    required_host_service_registrations = required_array(
        release_delivery_plan,
        "requiredHostServiceRegistrations",
        "C23 release delivery plan",
    )
    host_agent_registration = required_macos_host_service_registration(
        required_host_service_registrations,
        "host-agent",
    )
    host_edge_proxy_registration = required_macos_host_service_registration(
        required_host_service_registrations,
        "host-edge-proxy",
    )
    return MacOSHostPackageReleasePlan(
        release_delivery_plan_id=plan_id,
        product_version=required_string(
            release_delivery_plan,
            "productVersion",
            "C23 release delivery plan",
        ),
        expected_package_file_name=expected_package_file_name,
        macos_installer_package_identifier=required_string(
            release_delivery_plan,
            "macOSInstallerPackageIdentifier",
            "C23 macOS release delivery plan",
        ),
        host_agent_launchd_service_label=required_string(
            host_agent_registration,
            "name",
            "C23 host-agent service registration",
        ),
        host_edge_proxy_launchd_service_label=required_string(
            host_edge_proxy_registration,
            "name",
            "C23 host-edge-proxy service registration",
        ),
    )


def required_object(
    document: Mapping[str, Any], field_name: str, document_name: str
) -> Mapping[str, Any]:
    value = document.get(field_name)
    if not isinstance(value, dict):
        raise ProductDeliveryReleasePlanError(
            document_name + " requires object " + field_name
        )
    return value


def required_array(
    document: Mapping[str, Any], field_name: str, document_name: str
) -> list[Any]:
    value = document.get(field_name)
    if not isinstance(value, list):
        raise ProductDeliveryReleasePlanError(
            document_name + " requires array " + field_name
        )
    return value


def required_macos_host_service_registration(
    registrations: list[Any],
    role: str,
) -> Mapping[str, Any]:
    matching_registrations = [
        registration
        for registration in registrations
        if isinstance(registration, dict) and registration.get("role") == role
    ]
    if len(matching_registrations) != 1:
        raise ProductDeliveryReleasePlanError(
            "C23 macOS release delivery plan must declare exactly one "
            + role
            + " service registration"
        )
    registration = matching_registrations[0]
    if registration.get("manager") != "launchd":
        raise ProductDeliveryReleasePlanError(
            "C23 macOS " + role + " service registration manager must be launchd"
        )
    return registration


def required_string(
    document: Mapping[str, Any], field_name: str, document_name: str
) -> str:
    value = document.get(field_name)
    if not isinstance(value, str) or not value:
        raise ProductDeliveryReleasePlanError(
            document_name + " requires non-empty " + field_name
        )
    return value


def is_plain_file_name(value: str) -> bool:
    path = PurePosixPath(value)
    return (
        "/" not in value
        and "\\" not in value
        and path.name == value
        and value not in {".", ".."}
    )
