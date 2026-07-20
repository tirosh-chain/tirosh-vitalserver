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
    receipt identifier, and every required Host launchd identity.
    """

    release_delivery_plan_id: str
    product_version: str
    expected_package_file_name: str
    macos_installer_package_identifier: str
    macos_installer_signature_policy: str
    host_agent_launchd_service_label: str
    host_edge_proxy_launchd_service_label: str
    host_update_handoff_supervisor_launchd_service_label: str


@dataclass(frozen=True)
class WindowsHostMSIReleasePlan:
    """The C23 facts a Windows Host MSI is required to realize.

    The Product Delivery reader is the sole adapter that projects the C23
    installer identity and SCM registrations into Windows release tooling.
    This prevents a clean-Host evidence run from inventing a second set of
    service names or a separate product version.
    """

    release_delivery_plan_id: str
    product_version: str
    expected_msi_file_name: str
    host_agent_windows_scm_service_name: str
    host_edge_proxy_windows_scm_service_name: str
    host_update_handoff_supervisor_windows_scm_service_name: str


@dataclass(frozen=True)
class LinuxHostDEBReleasePlan:
    """The C23 facts a Linux Host DEB is required to realize."""

    release_delivery_plan_id: str
    product_version: str
    expected_deb_file_name: str
    host_agent_systemd_service_name: str
    host_edge_proxy_systemd_service_name: str
    host_update_handoff_supervisor_systemd_service_name: str


def load_selected_macos_host_package_release_plan(
    release_delivery_plans_document_path: Path,
    release_delivery_plan_id: str,
) -> MacOSHostPackageReleasePlan:
    """Read exactly one macOS C23 plan and project its package identity.

    The document is an external, release-process-owned input.  Absence,
    malformed JSON, duplicate IDs, wrong platform, and a schema-invalid plan
    remain explicit failures instead of becoming a guessed package identity.
    """

    selected_plan = load_selected_release_delivery_plan(
        release_delivery_plans_document_path, release_delivery_plan_id
    )
    return project_macos_host_package_release_plan(selected_plan)


def load_selected_windows_host_msi_release_plan(
    release_delivery_plans_document_path: Path,
    release_delivery_plan_id: str,
) -> WindowsHostMSIReleasePlan:
    """Read one Windows C23 plan and project its MSI/SCM identity."""

    selected_plan = load_selected_release_delivery_plan(
        release_delivery_plans_document_path, release_delivery_plan_id
    )
    return project_windows_host_msi_release_plan(selected_plan)


def load_selected_linux_host_deb_release_plan(
    release_delivery_plans_document_path: Path,
    release_delivery_plan_id: str,
) -> LinuxHostDEBReleasePlan:
    """Read one Linux C23 plan and project its DEB/systemd identity."""

    selected_plan = load_selected_release_delivery_plan(
        release_delivery_plans_document_path, release_delivery_plan_id
    )
    return project_linux_host_deb_release_plan(selected_plan)


def load_selected_release_delivery_plan(
    release_delivery_plans_document_path: Path,
    release_delivery_plan_id: str,
) -> Mapping[str, Any]:
    """Read exactly one validated C23 declaration without adding defaults."""

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
    return selected_plan


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
    host_update_handoff_supervisor_registration = required_macos_host_service_registration(
        required_host_service_registrations,
        "host-update-handoff-supervisor",
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
        macos_installer_signature_policy=required_macos_installer_signature_policy(
            release_delivery_plan
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
        host_update_handoff_supervisor_launchd_service_label=required_string(
            host_update_handoff_supervisor_registration,
            "name",
            "C23 host-update-handoff-supervisor service registration",
        ),
    )


def required_macos_installer_signature_policy(
    release_delivery_plan: Mapping[str, Any],
) -> str:
    """Read C23's explicit macOS package-signature policy without a default."""

    policy = required_string(
        release_delivery_plan,
        "macOSInstallerSignaturePolicy",
        "C23 macOS release delivery plan",
    )
    if policy not in {"unsigned", "developer-id"}:
        raise ProductDeliveryReleasePlanError(
            "C23 macOS installer signature policy must be unsigned or developer-id"
        )
    return policy


def project_windows_host_msi_release_plan(
    release_delivery_plan: Mapping[str, Any],
) -> WindowsHostMSIReleasePlan:
    """Turn one validated C23 plan into the Windows MSI boundary vocabulary."""

    plan_id = required_string(release_delivery_plan, "id", "C23 release delivery plan")
    if release_delivery_plan.get("platform") != "windows":
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plan must target windows for a Windows Host MSI"
        )
    if release_delivery_plan.get("providerKind") != "windows-hyperv-scm":
        raise ProductDeliveryReleasePlanError(
            "C23 Windows release delivery plan must name providerKind windows-hyperv-scm"
        )
    intended_installer_artifact = required_object(
        release_delivery_plan,
        "intendedInstallerArtifact",
        "C23 release delivery plan",
    )
    if intended_installer_artifact.get("kind") != "msi":
        raise ProductDeliveryReleasePlanError(
            "C23 Windows intended installer artifact kind must be msi"
        )
    expected_msi_file_name = required_string(
        intended_installer_artifact,
        "expectedName",
        "C23 intended installer artifact",
    )
    if not is_plain_file_name(expected_msi_file_name):
        raise ProductDeliveryReleasePlanError(
            "C23 Windows intended installer artifact expectedName must be one MSI file name"
        )
    registrations = required_array(
        release_delivery_plan,
        "requiredHostServiceRegistrations",
        "C23 release delivery plan",
    )
    return WindowsHostMSIReleasePlan(
        release_delivery_plan_id=plan_id,
        product_version=required_string(
            release_delivery_plan, "productVersion", "C23 release delivery plan"
        ),
        expected_msi_file_name=expected_msi_file_name,
        host_agent_windows_scm_service_name=required_windows_host_service_registration(
            registrations, "host-agent"
        ),
        host_edge_proxy_windows_scm_service_name=required_windows_host_service_registration(
            registrations, "host-edge-proxy"
        ),
        host_update_handoff_supervisor_windows_scm_service_name=required_windows_host_service_registration(
            registrations, "host-update-handoff-supervisor"
        ),
    )


def project_linux_host_deb_release_plan(
    release_delivery_plan: Mapping[str, Any],
) -> LinuxHostDEBReleasePlan:
    """Turn one validated C23 plan into Linux DEB/systemd vocabulary."""

    plan_id = required_string(release_delivery_plan, "id", "C23 release delivery plan")
    if release_delivery_plan.get("platform") != "linux":
        raise ProductDeliveryReleasePlanError(
            "C23 release delivery plan must target linux for a Linux Host DEB"
        )
    if release_delivery_plan.get("providerKind") != "linux-kvm-libvirt-systemd":
        raise ProductDeliveryReleasePlanError(
            "C23 Linux release delivery plan must name providerKind linux-kvm-libvirt-systemd"
        )
    installer = required_object(
        release_delivery_plan, "intendedInstallerArtifact", "C23 release delivery plan"
    )
    if installer.get("kind") != "deb":
        raise ProductDeliveryReleasePlanError(
            "C23 Linux intended installer artifact kind must be deb"
        )
    expected_deb_file_name = required_string(
        installer, "expectedName", "C23 intended installer artifact"
    )
    if not is_plain_file_name(expected_deb_file_name):
        raise ProductDeliveryReleasePlanError(
            "C23 Linux intended installer artifact expectedName must be one DEB file name"
        )
    registrations = required_array(
        release_delivery_plan,
        "requiredHostServiceRegistrations",
        "C23 release delivery plan",
    )
    return LinuxHostDEBReleasePlan(
        release_delivery_plan_id=plan_id,
        product_version=required_string(
            release_delivery_plan, "productVersion", "C23 release delivery plan"
        ),
        expected_deb_file_name=expected_deb_file_name,
        host_agent_systemd_service_name=required_linux_host_service_registration(
            registrations, "host-agent"
        ),
        host_edge_proxy_systemd_service_name=required_linux_host_service_registration(
            registrations, "host-edge-proxy"
        ),
        host_update_handoff_supervisor_systemd_service_name=required_linux_host_service_registration(
            registrations, "host-update-handoff-supervisor"
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


def required_windows_host_service_registration(
    registrations: list[Any], role: str
) -> str:
    """Return one C23 Windows SCM service name, never an inferred default."""

    matching_registrations = [
        registration
        for registration in registrations
        if isinstance(registration, dict) and registration.get("role") == role
    ]
    if len(matching_registrations) != 1:
        raise ProductDeliveryReleasePlanError(
            "C23 Windows release delivery plan must declare exactly one "
            + role
            + " service registration"
        )
    registration = matching_registrations[0]
    if registration.get("manager") != "windows-scm":
        raise ProductDeliveryReleasePlanError(
            "C23 Windows " + role + " service registration manager must be windows-scm"
        )
    return required_string(
        registration, "name", "C23 Windows " + role + " service registration"
    )


def required_linux_host_service_registration(
    registrations: list[Any], role: str
) -> str:
    """Return one C23 systemd unit name without inventing a service default."""

    matching_registrations = [
        registration
        for registration in registrations
        if isinstance(registration, dict) and registration.get("role") == role
    ]
    if len(matching_registrations) != 1:
        raise ProductDeliveryReleasePlanError(
            "C23 Linux release delivery plan must declare exactly one "
            + role
            + " service registration"
        )
    registration = matching_registrations[0]
    if registration.get("manager") != "systemd":
        raise ProductDeliveryReleasePlanError(
            "C23 Linux " + role + " service registration manager must be systemd"
        )
    name = required_string(
        registration, "name", "C23 Linux " + role + " service registration"
    )
    if not name.endswith(".service"):
        raise ProductDeliveryReleasePlanError(
            "C23 Linux " + role + " service registration name must end with .service"
        )
    return name


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
