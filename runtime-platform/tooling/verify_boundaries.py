#!/usr/bin/env python3
"""Verify that runtime-platform remains an independent implementation root."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
from typing import Iterable, List, Sequence


REQUIRED_DIRECTORIES: Sequence[Path] = (
    Path("contracts"),
    Path("services/host-agent"),
    Path("services/host-edge-proxy"),
    Path("services/host-installation-manager"),
    Path("services/host-updater"),
    Path("services/guest-product-process-supervisor"),
    Path("services/guest-product-release-manager"),
    Path("services/guest-product-release-effect-executor"),
    Path("services/guest-bundled-upstream-image-set-manager"),
    Path("services/guest-bundled-upstream-image-set-effect-executor"),
    Path("services/host-platform-release-effect-executor"),
    Path("services/guest-runtime"),
    Path("services/recorder-gateway"),
    Path("services/runtime-pwa"),
    Path("interfaces/platformctl"),
    Path("interfaces/runtime-console-control-contract"),
    Path("interfaces/runtime-console-web"),
    Path("interfaces/runtime-console-desktop"),
    Path("providers/macos-virtualization"),
    Path("product"),
    Path("acceptance/features"),
    Path("acceptance/reference-fixtures"),
    Path("acceptance/harness"),
    Path("tooling"),
)

# Each Runtime Platform product process must retain its bounded-context name
# in its layer directory.  An import path, stack trace, or source inventory
# must not reduce Host Agent, Guest Runtime, Guest Product Process Supervisor,
# or Host Edge Proxy to a generic role label.
CONTEXTUAL_PRODUCT_PROCESS_LAYER_DIRECTORIES: Sequence[Path] = (
    Path("services/host-agent/internal/hostagentdomain"),
    Path("services/host-agent/internal/hostagentapplication"),
    Path("services/host-agent/internal/hostagentcontrolhttpapi"),
    Path("services/guest-runtime/internal/guestruntimedomain"),
    Path("services/guest-runtime/internal/guestruntimeapplication"),
    Path("services/guest-runtime/internal/guestruntimecontrolhttpapi"),
    Path("services/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"),
    Path("services/guest-product-process-supervisor/internal/guestproductprocesssupervisorapplication"),
    Path("services/guest-product-process-supervisor/internal/adapters/guestproductdeploymentconfigurationfile"),
    Path("services/guest-product-release-manager/internal/guestproductreleasemanagerdomain"),
    Path("services/guest-product-release-manager/internal/guestproductreleasemanagerapplication"),
    Path("services/guest-product-release-manager/internal/guestproductreleasemanagerhttpapi"),
    Path("services/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"),
    Path("services/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutorapplication"),
    Path("services/guest-product-release-effect-executor/internal/adapters/releaseeffectconfigurationfile"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerapplication"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerhttpapi"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/adapters/guestbundledupstreamimagesetmanagerconfigurationfile"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutordomain"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutorapplication"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal/adapters/imageseteffectconfigurationfile"),
    Path("services/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutordomain"),
    Path("services/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutorapplication"),
    Path("services/host-platform-release-effect-executor/internal/adapters/hostplatformreleaseeffectconfigurationfile"),
    Path("services/host-edge-proxy/internal/hostedgeproxydomain"),
    Path("services/host-edge-proxy/internal/hostedgeproxyhttpserver"),
    Path("services/host-edge-proxy/internal/hostedgeproxydeployment"),
    Path("services/host-installation-manager/internal/hostinstallationmanagerdomain"),
    Path("services/host-installation-manager/internal/hostinstallationmanagerapplication"),
    Path("services/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"),
    Path("services/host-installation-manager/internal/hostplatformstagedreleaseupdateapplication"),
    Path("services/host-installation-manager/internal/adapters/macoshostinstallationfootprint"),
    Path("services/host-updater/internal/hostupdaterdomain"),
    Path("services/host-updater/internal/hostupdaterstagedupdatecompletionapplication"),
)

FORBIDDEN_GENERIC_PRODUCT_PROCESS_LAYER_DIRECTORIES: Sequence[Path] = (
    Path("services/host-agent/internal/domain"),
    Path("services/host-agent/internal/application"),
    Path("services/host-agent/internal/httpapi"),
    Path("services/guest-runtime/internal/domain"),
    Path("services/guest-runtime/internal/application"),
    Path("services/guest-runtime/internal/httpapi"),
    Path("services/guest-product-process-supervisor/internal/domain"),
    Path("services/guest-product-process-supervisor/internal/application"),
    Path("services/guest-product-process-supervisor/internal/guestproductprocessdeployment"),
    Path("services/guest-product-process-supervisor/internal/adapters/configurationfile"),
    Path("services/guest-product-release-manager/internal/domain"),
    Path("services/guest-product-release-manager/internal/application"),
    Path("services/guest-product-release-manager/internal/httpapi"),
    Path("services/guest-product-release-effect-executor/internal/domain"),
    Path("services/guest-product-release-effect-executor/internal/application"),
    Path("services/guest-product-release-effect-executor/internal/adapters/configurationfile"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/domain"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/application"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/httpapi"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/adapters/configurationfile"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal/domain"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal/application"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal/adapters/configurationfile"),
    Path("services/host-platform-release-effect-executor/internal/domain"),
    Path("services/host-platform-release-effect-executor/internal/application"),
    Path("services/host-platform-release-effect-executor/internal/adapters/configurationfile"),
    Path("services/host-edge-proxy/internal/domain"),
    Path("services/host-edge-proxy/internal/edgehttpserver"),
    Path("services/host-edge-proxy/internal/deployment"),
    Path("services/host-installation-manager/internal/domain"),
    Path("services/host-installation-manager/internal/application"),
    Path("services/host-updater/internal/domain"),
    Path("services/host-updater/internal/application"),
)

PRODUCT_PROCESS_INTERNAL_DIRECTORIES: Sequence[Path] = (
    Path("services/host-agent/internal"),
    Path("services/guest-runtime/internal"),
    Path("services/guest-product-process-supervisor/internal"),
    Path("services/guest-product-release-manager/internal"),
    Path("services/guest-product-release-effect-executor/internal"),
    Path("services/guest-bundled-upstream-image-set-manager/internal"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal"),
    Path("services/host-platform-release-effect-executor/internal"),
    Path("services/host-edge-proxy/internal"),
    Path("services/host-installation-manager/internal"),
    Path("services/host-updater/internal"),
)

CONTEXTUAL_PRODUCT_PROCESS_APPLICATION_DIRECTORIES: Sequence[Path] = (
    Path("services/host-agent/internal/hostagentapplication"),
    Path("services/guest-runtime/internal/guestruntimeapplication"),
    Path("services/guest-product-process-supervisor/internal/guestproductprocesssupervisorapplication"),
    Path("services/guest-product-release-manager/internal/guestproductreleasemanagerapplication"),
    Path("services/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutorapplication"),
    Path("services/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerapplication"),
    Path("services/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutorapplication"),
    Path("services/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutorapplication"),
    Path("services/host-updater/internal/hostupdaterstagedupdatecompletionapplication"),
    Path("services/host-installation-manager/internal/hostinstallationmanagerapplication"),
    Path("services/host-installation-manager/internal/hostplatformstagedreleaseupdateapplication"),
)

# Time Authority, Recorder Observation Catalog, and Telemetry Pipeline are
# independent Guest Runtime owners. A single "operational" port file makes it
# look as if their SQLite resources, providers, and operation lifecycles form
# one aggregate. Keep their application boundary vocabulary separate.
FORBIDDEN_GENERIC_GUEST_RUNTIME_APPLICATION_FILES: Sequence[Path] = (
    Path(
        "services/guest-runtime/internal/guestruntimeapplication/"
        "guest_runtime_operational_application_ports.go"
    ),
)

# C26/C27/C28/C30 are all Host Updater contracts.  Their domain models are
# deliberately more specific than `Artifact`, `Plan`, or `Report` because the
# Host Agent update journal, Guest archive export, and release build all have
# different artifacts and evidence.  Keep the most easily reintroduced
# generic public names out of the next-updater domain.
HOST_UPDATER_DOMAIN_DIRECTORY = Path(
    "services/host-updater/internal/hostupdaterdomain"
)
AMBIGUOUS_HOST_UPDATER_DOMAIN_DECLARATION = re.compile(
    r"^\s*(?:type\s+(?:Artifact|RollbackPlan|LayerPlan|UpdateIssue|UpdateEvidenceReference|UpdateLayerExecutionEvidence|UpdateRollbackEvidence|UpdateExecutionReport|UpdateCompletionCommand)\b|func\s+(?:PlanStagedUpdate|ComposeUpdateCompletionCommand|ValidateUpdateExecutionReport)\s*\()",
    re.MULTILINE,
)

# Recorder Gateway is a separately deployable Guest product process.  Its
# TypeScript source tree must carry the bounded context and managed resource
# in every layer name, for the same reason that Go services use contextual
# `internal/` package names above.  A stack trace containing `src/domain` or
# `src/application` does not identify its state owner.
RECORDER_GATEWAY_SOURCE_DIRECTORY = Path("services/recorder-gateway/src")
CONTEXTUAL_RECORDER_GATEWAY_LAYER_DIRECTORIES: Sequence[Path] = (
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "recordergatewaydomain",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "recordergatewayapplication",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "adapters/recordergatewayingressdurablestatefile",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "adapters/recordergatewayinbound",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "adapters/vitalserverpacketdeliverysocketio",
)
FORBIDDEN_GENERIC_RECORDER_GATEWAY_LAYER_DIRECTORIES: Sequence[Path] = (
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "domain",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "application",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "adapters/file",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "adapters/inbound",
    RECORDER_GATEWAY_SOURCE_DIRECTORY / "adapters/vitalserverdelivery",
)

# Recorder Gateway has one product-specific outbound delivery contract. Its
# adapter directory must name VitalServer *packet delivery* rather than a
# generic network direction such as `upstream`, which could mean External
# Upstream observation, Outbound Relay, or a Host proxy.
RECORDER_GATEWAY_ADAPTER_DIRECTORY = Path("services/recorder-gateway/src/adapters")
REQUIRED_RECORDER_GATEWAY_VITALSERVER_DELIVERY_ADAPTER_DIRECTORY = (
    RECORDER_GATEWAY_ADAPTER_DIRECTORY / "vitalserverpacketdeliverysocketio"
)
FORBIDDEN_GENERIC_RECORDER_GATEWAY_ADAPTER_DIRECTORIES: Sequence[Path] = (
    RECORDER_GATEWAY_ADAPTER_DIRECTORY / "upstream",
)

# Application services and their ports are cross-layer contracts. Their
# exported method names must retain the aggregate/action meaning even when a
# reader sees only a stack trace or a search result without the receiver type.
# Generic `Get` and bare action verbs make it impossible to distinguish a
# state-store read from a cache lookup, or a topology command from an archive
# effect.
AMBIGUOUS_PRODUCT_PROCESS_APPLICATION_METHOD = re.compile(
    r"^\s*(?:func\s+(?:\([^)]*\)\s+)?|)(?:Get[A-Za-z0-9_]*|Apply|Export|Emit|Ingest|CreateSession|ExecuteResource|Reference|Upload|VerifyIndex|New)\s*\(",
    re.MULTILINE,
)

AMBIGUOUS_RECORDER_GATEWAY_APPLICATION_METHOD = re.compile(
    r"^\s*(?:public\s+|private\s+|protected\s+)?(?:async\s+)?(?:get[A-Z][A-Za-z0-9_]*|apply|export|emit|ingest|createSession|executeResource|reference|upload|verifyIndex)\s*\(",
    re.MULTILINE,
)

SCANNED_DIRECTORIES: Sequence[Path] = (
    Path("contracts"),
    Path("services"),
    Path("providers"),
    Path("product"),
    Path("interfaces"),
)

# These directories contain generated tooling state or explicit build/release
# evidence. They are not implementation source and therefore must not be
# interpreted as hidden dependencies by the independent-root checker.
NON_SOURCE_ARTIFACT_DIRECTORIES = frozenset(
    {
        ".tmp",
        ".venv",
        ".build",
        ".swiftpm",
        "node_modules",
        "__pycache__",
        ".pytest_cache",
    }
)

PRODUCTION_FILE_SUFFIXES = frozenset(
    {
        ".bash",
        ".cjs",
        ".go",
        ".js",
        ".json",
        ".mjs",
        ".py",
        ".sh",
        ".swift",
        ".toml",
        ".ts",
        ".tsx",
        ".yaml",
        ".yml",
    }
)

FORBIDDEN_LEGACY_MARKERS: Sequence[str] = (
    "apps/vitalserver-",
    "packages/vitalserver-",
    "@tirosh/vitalserver-",
    "tirosh-vitalserver",
    "tirosh_vitalserver",
    "github.com/tirosh/vitalserver-",
)

# Runtime Platform's installed Host reads only the stable Update Bootstrap
# Envelope.  These legacy manifest gates require an installed updater to
# understand the evolving product specification and would silently restore
# the compatibility problem that the bundle-owned next updater removes.
FORBIDDEN_LEGACY_UPDATE_GATE_MARKERS: Sequence[str] = (
    "minUpdaterVersion",
    "requiresTwoPhaseUpdate",
)

FORBIDDEN_LEGACY_RELATIVE_PATH = re.compile(r"(?:\.\./)+(?:apps|packages)/")
TEMPORARY_WORK_ORDER_PATH_COMPONENT = re.compile(r"^phase(?:[-_].*|\d.*)?$", re.IGNORECASE)


@dataclass(frozen=True)
class Violation:
    """A repository boundary failure that must be fixed before merge."""

    code: str
    path: Path
    message: str

    def render(self, root: Path) -> str:
        try:
            relative_path = self.path.relative_to(root)
        except ValueError:
            relative_path = self.path
        return "[{code}] {path}: {message}".format(
            code=self.code,
            path=relative_path,
            message=self.message,
        )


def validate_required_directories(root: Path) -> List[Violation]:
    """Require the declared responsibility layout to remain explicit."""

    violations = []
    for relative_path in REQUIRED_DIRECTORIES:
        path = root / relative_path
        if not path.is_dir():
            violations.append(
                Violation(
                    code="required-directory-missing",
                    path=path,
                    message="required responsibility directory is missing",
                )
            )
    return violations


def validate_contextual_product_process_layer_names(root: Path) -> List[Violation]:
    """Keep product-process layer names readable without opening source files.

    The check activates only after the relevant `internal/` tree exists.  This
    keeps an intentionally empty scaffold distinct from a real product process
    that silently reintroduces generic layer directories.
    """

    if not any((root / directory).is_dir() for directory in PRODUCT_PROCESS_INTERNAL_DIRECTORIES):
        return []

    violations = []
    for relative_path in CONTEXTUAL_PRODUCT_PROCESS_LAYER_DIRECTORIES:
        path = root / relative_path
        if not path.is_dir():
            violations.append(
                Violation(
                    code="contextual-product-process-layer-missing",
                    path=path,
                    message=(
                        "Runtime Platform product-process layer must name its bounded context and role"
                    ),
                )
            )
    for relative_path in FORBIDDEN_GENERIC_PRODUCT_PROCESS_LAYER_DIRECTORIES:
        path = root / relative_path
        if path.is_dir():
            violations.append(
                Violation(
                    code="generic-product-process-layer-not-allowed",
                    path=path,
                    message=(
                        "generic layer directory hides bounded-context ownership or its external mechanism; "
                        "use the explicit Host Agent, Guest Runtime, Guest Product Process Supervisor, Host Edge Proxy, or Host Updater layer name"
                    ),
                )
            )
    return violations


def validate_contextual_product_process_application_method_names(root: Path) -> List[Violation]:
    """Reject ambiguous exported verbs at Runtime Platform application boundaries."""

    violations = []
    for relative_directory in CONTEXTUAL_PRODUCT_PROCESS_APPLICATION_DIRECTORIES:
        application_directory = root / relative_directory
        if not application_directory.is_dir():
            continue
        for path in sorted(application_directory.rglob("*.go")):
            try:
                content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as error:
                violations.append(
                    Violation(
                        code="product-process-application-source-unreadable",
                        path=path,
                        message="could not inspect Runtime Platform product-process application source: {0}".format(
                            error
                        ),
                    )
                )
                continue
            match = AMBIGUOUS_PRODUCT_PROCESS_APPLICATION_METHOD.search(content)
            if match is not None:
                violations.append(
                    Violation(
                        code="ambiguous-product-process-application-method",
                        path=path,
                        message=(
                            "Runtime Platform product-process application method hides its aggregate or effect; "
                            "use a contextual Read…, List…, Apply…, Ingest…, or Execute…Command name"
                        ),
                    )
                )
    return violations


def validate_guest_runtime_application_port_file_names(root: Path) -> List[Violation]:
    """Reject one generic operational port module spanning distinct owners."""

    violations = []
    for relative_path in FORBIDDEN_GENERIC_GUEST_RUNTIME_APPLICATION_FILES:
        path = root / relative_path
        if path.is_file():
            violations.append(
                Violation(
                    code="generic-guest-runtime-operational-port-file-not-allowed",
                    path=path,
                    message=(
                        "Guest Runtime Time Authority, Recorder Observation Catalog, and Telemetry Pipeline "
                        "ports must retain their separate bounded-context names"
                    ),
                )
            )
    return violations


def validate_host_updater_domain_declaration_names(root: Path) -> List[Violation]:
    """Keep C26/C27/C28/C30 model names distinct from other update domains."""

    domain_directory = root / HOST_UPDATER_DOMAIN_DIRECTORY
    if not domain_directory.is_dir():
        return []

    violations = []
    for path in sorted(domain_directory.rglob("*.go")):
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            violations.append(
                Violation(
                    code="host-updater-domain-source-unreadable",
                    path=path,
                    message="could not inspect Host Updater domain source: {0}".format(error),
                )
            )
            continue
        match = AMBIGUOUS_HOST_UPDATER_DOMAIN_DECLARATION.search(content)
        if match is not None:
            violations.append(
                Violation(
                    code="ambiguous-host-updater-domain-declaration",
                    path=path,
                    message=(
                        "Host Updater C26/C27/C28/C30 declaration hides the staged product-update context; "
                        "use ProductUpdate… or StagedProductUpdate… terminology"
                    ),
                )
            )
    return violations


def validate_contextual_recorder_gateway_layer_names(root: Path) -> List[Violation]:
    """Keep Recorder Gateway source layers readable without opening a module."""

    source_directory = root / RECORDER_GATEWAY_SOURCE_DIRECTORY
    if not source_directory.is_dir():
        return []

    violations = []
    for relative_path in CONTEXTUAL_RECORDER_GATEWAY_LAYER_DIRECTORIES:
        path = root / relative_path
        if not path.is_dir():
            violations.append(
                Violation(
                    code="contextual-recorder-gateway-layer-missing",
                    path=path,
                    message=(
                        "Recorder Gateway source layer must name its bounded context and managed boundary"
                    ),
                )
            )
    for relative_path in FORBIDDEN_GENERIC_RECORDER_GATEWAY_LAYER_DIRECTORIES:
        path = root / relative_path
        if path.is_dir():
            violations.append(
                Violation(
                    code="generic-recorder-gateway-layer-not-allowed",
                    path=path,
                    message=(
                        "generic Recorder Gateway layer hides its bounded context or managed resource; "
                        "use a recordergateway… layer name"
                    ),
                )
            )
    return violations


def validate_contextual_recorder_gateway_application_method_names(root: Path) -> List[Violation]:
    """Reject generic verbs at the Recorder Gateway application boundary."""

    application_directory = root / RECORDER_GATEWAY_SOURCE_DIRECTORY / "recordergatewayapplication"
    if not application_directory.is_dir():
        return []

    violations = []
    for path in sorted(application_directory.rglob("*.ts")):
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            violations.append(
                Violation(
                    code="recorder-gateway-application-source-unreadable",
                    path=path,
                    message="could not inspect Recorder Gateway application source: {0}".format(error),
                )
            )
            continue
        match = AMBIGUOUS_RECORDER_GATEWAY_APPLICATION_METHOD.search(content)
        if match is not None:
            violations.append(
                Violation(
                    code="ambiguous-recorder-gateway-application-method",
                    path=path,
                    message=(
                        "Recorder Gateway application method hides its managed packet, receipt, durable ingress state, cold-path capture, or VitalServer delivery replay effect; "
                        "use a contextual Admit…, Read…, Replay…, Persist…, or Deliver… name"
                    ),
                )
            )
    return violations


def validate_recorder_gateway_vitalserver_delivery_adapter_name(root: Path) -> List[Violation]:
    """Keep the Recorder Gateway delivery adapter readable as a VitalServer boundary."""

    adapter_root = root / RECORDER_GATEWAY_ADAPTER_DIRECTORY
    if not adapter_root.is_dir():
        return []

    violations = []
    required_directory = root / REQUIRED_RECORDER_GATEWAY_VITALSERVER_DELIVERY_ADAPTER_DIRECTORY
    if not required_directory.is_dir():
        violations.append(
            Violation(
                code="recorder-gateway-vitalserver-delivery-adapter-missing",
                path=required_directory,
                message=(
                    "Recorder Gateway delivery adapter directory must name the VitalServer packet-delivery boundary"
                ),
            )
        )
    for relative_path in FORBIDDEN_GENERIC_RECORDER_GATEWAY_ADAPTER_DIRECTORIES:
        path = root / relative_path
        if path.is_dir():
            violations.append(
                Violation(
                    code="generic-recorder-gateway-delivery-adapter-not-allowed",
                    path=path,
                    message=(
                        "generic upstream adapter hides the VitalServer packet-delivery contract; "
                        "use adapters/vitalserverpacketdeliverysocketio"
                    ),
                )
            )
    return violations


def validate_no_symlinks(root: Path) -> List[Violation]:
    """Reject symlinks so the new root cannot hide an external source dependency."""

    violations = []
    for path in sorted(root.rglob("*")):
        relative_path = path.relative_to(root)
        if any(
            part in NON_SOURCE_ARTIFACT_DIRECTORIES
            for part in relative_path.parts
        ):
            continue
        if path.is_symlink():
            violations.append(
                Violation(
                    code="symlink-not-allowed",
                    path=path,
                    message="symlinks are not allowed in the independent implementation root",
                )
            )
    return violations


def validate_no_temporary_work_order_paths(root: Path) -> List[Violation]:
    """Keep persistent product paths named for domain responsibility, not order."""

    violations = []
    for path in sorted(root.rglob("*")):
        relative_path = path.relative_to(root)
        if any(part in NON_SOURCE_ARTIFACT_DIRECTORIES for part in relative_path.parts):
            continue
        temporary_component = next(
            (part for part in relative_path.parts if TEMPORARY_WORK_ORDER_PATH_COMPONENT.fullmatch(part)),
            None,
        )
        if temporary_component is not None:
            violations.append(
                Violation(
                    code="temporary-work-order-path-not-allowed",
                    path=path,
                    message=(
                        "persistent path component '{0}' encodes temporary delivery order; "
                        "name the owner, domain, boundary, or role instead"
                    ).format(temporary_component),
                )
            )
    return violations


def iter_production_files(root: Path) -> Iterable[Path]:
    """Yield code/configuration files where legacy source coupling is prohibited."""

    for relative_directory in SCANNED_DIRECTORIES:
        directory = root / relative_directory
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*")):
            relative_path = path.relative_to(root)
            if any(part in NON_SOURCE_ARTIFACT_DIRECTORIES for part in relative_path.parts):
                continue
            if path.is_file() and path.suffix.lower() in PRODUCTION_FILE_SUFFIXES:
                yield path


def validate_no_legacy_coupling(root: Path) -> List[Violation]:
    """Reject source and configuration references to the parent legacy workspace."""

    violations = []
    for path in iter_production_files(root):
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            violations.append(
                Violation(
                    code="production-file-unreadable",
                    path=path,
                    message="could not inspect production file: {0}".format(error),
                )
            )
            continue

        if FORBIDDEN_LEGACY_RELATIVE_PATH.search(content):
            violations.append(
                Violation(
                    code="legacy-coupling",
                    path=path,
                    message="forbidden relative path to parent legacy workspace",
                )
            )
            continue
        for marker in FORBIDDEN_LEGACY_MARKERS:
            if marker in content:
                violations.append(
                    Violation(
                        code="legacy-coupling",
                        path=path,
                        message="forbidden legacy coupling marker: {0}".format(marker),
                    )
                )
                break
    return violations


def validate_no_legacy_update_gates(root: Path) -> List[Violation]:
    """Keep evolving product-update policy out of the installed Host baseline."""

    violations = []
    for path in iter_production_files(root):
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            # The legacy-coupling check reports the typed unreadable-file
            # violation once; do not duplicate that evidence here.
            continue
        for marker in FORBIDDEN_LEGACY_UPDATE_GATE_MARKERS:
            if marker in content:
                violations.append(
                    Violation(
                        code="legacy-update-gate-not-allowed",
                        path=path,
                        message=(
                            "installed Runtime Platform code and configuration must not use "
                            "{0}; the Host verifies the stable bootstrap envelope and the "
                            "bundle-owned next updater interprets the product update specification"
                        ).format(marker),
                    )
                )
                break
    return violations


def validate(root: Path) -> List[Violation]:
    """Run every independent implementation-root boundary check."""

    if not root.is_dir():
        return [
            Violation(
                code="root-missing",
                path=root,
                message="runtime-platform root directory does not exist",
            )
        ]

    violations = []
    violations.extend(validate_required_directories(root))
    violations.extend(validate_contextual_product_process_layer_names(root))
    violations.extend(validate_contextual_product_process_application_method_names(root))
    violations.extend(validate_guest_runtime_application_port_file_names(root))
    violations.extend(validate_host_updater_domain_declaration_names(root))
    violations.extend(validate_contextual_recorder_gateway_layer_names(root))
    violations.extend(validate_contextual_recorder_gateway_application_method_names(root))
    violations.extend(validate_recorder_gateway_vitalserver_delivery_adapter_name(root))
    violations.extend(validate_no_symlinks(root))
    violations.extend(validate_no_temporary_work_order_paths(root))
    violations.extend(validate_no_legacy_coupling(root))
    violations.extend(validate_no_legacy_update_gates(root))
    return violations


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="runtime-platform root to validate",
    )
    arguments = parser.parse_args(argv)
    root = arguments.root.resolve()

    violations = validate(root)
    if not violations:
        print("runtime-platform boundary verification passed")
        return 0

    print("runtime-platform boundary verification failed:")
    for violation in violations:
        print("  {0}".format(violation.render(root)))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
