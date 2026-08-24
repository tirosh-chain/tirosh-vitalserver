from __future__ import annotations

from dataclasses import dataclass

from tirosh_vitalserver.devtools.core.helper_effect_configuration import (
    GUEST_OWNER_EFFECT_CONFIGURATION_KEYS,
    GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA,
)
from tirosh_vitalserver.devtools.core.preflight import (
    PreflightCheck,
    PreflightReport,
    PreflightStatus,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle import (
    SCHEMA_VERSION as ENVELOPE_SCHEMA_VERSION,
)

HANDOFF_SCHEMA_VERSION = "vitalserver.update-bootstrap-handoff/v2"
HOST_PLATFORM_PHASES = (
    "requested",
    "prepared",
    "previous-quiesced",
    "interfaces-published",
    "target-activated",
    "target-services-loaded",
    "compensating",
    "compensated",
    "completed",
    "failed",
)
HANDOFF_RECOVERY_COMMANDS = (
    "verify-update-bootstrap",
    "apply-update-bootstrap",
    "prove-update-bootstrap",
    "resume-update-bootstrap-handoff",
    "settle-update-bootstrap-handoff",
    "fail-update-bootstrap",
)
COMPOSE_INPUT_NAMES = (
    "VM_UPDATE_ID",
    "VM_UPDATE_SPECIFICATION_ID",
    "VM_UPDATE_PRODUCT_VERSION",
    "VM_UPDATE_RUNTIME_VERSION",
    "VM_UPDATE_ISSUED_AT",
    "VM_UPDATE_PUBLISHER_KEY_ID",
    "VM_UPDATE_PUBLISHER_PRIVATE_KEY",
    "VM_UPDATE_BOOTSTRAP_TRUST_STORE",
    "VM_UPDATE_CONTAINER_ARTIFACT",
    "VM_UPDATE_CONTAINER_ROLLBACK_ARTIFACT",
    "VM_UPDATE_CONTAINER_EFFECT_CONFIGURATION",
    "VM_UPDATE_GUEST_RUNTIME_ARTIFACT",
    "VM_UPDATE_GUEST_RUNTIME_ROLLBACK_ARTIFACT",
    "VM_UPDATE_GUEST_RUNTIME_EFFECT_CONFIGURATION",
    "VM_UPDATE_HOST_PLATFORM_ARCHIVE_COMPOSITION",
    "VM_UPDATE_HOST_PLATFORM_ROLLBACK_ARTIFACT",
    "VM_UPDATE_HOST_PLATFORM_INSTALLATION_ID",
    "VM_UPDATE_HOST_PLATFORM_APPLY_REVISION",
    "VM_UPDATE_HOST_PLATFORM_APPLY_RELEASE_ID",
    "VM_UPDATE_HOST_PLATFORM_APPLY_RELEASE_VERSION",
    "VM_UPDATE_HOST_PLATFORM_APPLY_SLOT_RELATIVE_PATH",
    "VM_UPDATE_HOST_PLATFORM_ROLLBACK_REVISION",
    "VM_UPDATE_HOST_PLATFORM_ROLLBACK_RELEASE_ID",
    "VM_UPDATE_HOST_PLATFORM_ROLLBACK_RELEASE_VERSION",
    "VM_UPDATE_HOST_PLATFORM_ROLLBACK_SLOT_RELATIVE_PATH",
)
SECRET_INPUT_NAMES = frozenset({"VM_UPDATE_PUBLISHER_PRIVATE_KEY"})
MUTATING_CONFIRM_INPUT = "VM_UPDATE_APPLY_SMOKE_CONFIRM"
MUTATING_CONFIRM_REQUIRED_VALUE = "YES"

SOURCE_PACKAGE_MAKEFILE = "make/vm/package.mk"
SOURCE_ROOT_MAKEFILE = "Makefile"
SOURCE_ENVELOPE_POLICY = (
    "apps/vitalserver-macos-runtime/Sources/Domain/Policies/"
    "UpdateBootstrapEnvelopePolicy.swift"
)
SOURCE_HANDOFF_POLICY = (
    "apps/vitalserver-macos-runtime/Sources/Domain/Policies/"
    "UpdateBootstrapHandoffPolicy.swift"
)
SOURCE_HANDOFF_CONTRACT = (
    "apps/vitalserver-macos-runtime/Sources/Contracts/Shared/"
    "UpdateBootstrapHandoffContracts.swift"
)
SOURCE_RUNTIME_LIFECYCLE = (
    "apps/vitalserver-macos-runtime/Sources/Adapters/Inbound/CLI/Commands/"
    "RuntimeLifecycleCommand.swift"
)
SOURCE_HOST_PLATFORM_CONTRACTS = (
    "apps/vitalserver-macos-runtime/Sources/Contracts/Shared/"
    "HostPlatformInstallationContracts.swift"
)
SOURCE_PROVE_USECASE = (
    "apps/vitalserver-macos-runtime/Sources/Application/UseCases/"
    "UpdateRuntime/ProveUpdateBootstrapLifecycleUseCase.swift"
)
SOURCE_PROVE_COMPOSITION = (
    "apps/vitalserver-macos-runtime/Sources/Hosts/CLI/ProcessBoundary/"
    "RuntimeUpdateBootstrapComposition.swift"
)
SOURCE_INSTALLED_PATHS = (
    "apps/vitalserver-macos-runtime/Sources/Adapters/Outbound/FileSystem/"
    "InstalledRuntimePaths.swift"
)
SOURCE_VM_CONFIG_MAKEFILE = "make/vm/config.mk"
SOURCE_RELEASE_DEV = "apps/vitalserver-macos-runtime/release-dev.json"
INSTALLED_RUNTIME_HOME_INPUT = "VM_UPDATE_INSTALLED_RUNTIME_HOME"
DEFAULT_PRODUCT_ROOT_MARKER = 'defaultProductRoot = URL(fileURLWithPath: "'

HANDOFF_POLICY_GUEST_ENDPOINT_EVIDENCE = (
    "guestControlBaseURL: String",
    "guestControlBaseURL: guestControlBaseURL",
)
HANDOFF_CONTRACT_GUEST_ENDPOINT_EVIDENCE = (
    "case guestControlBaseURL",
    "forKey: .guestControlBaseURL",
)


@dataclass(frozen=True)
class FieldProofTextSource:
    name: str
    status: PreflightStatus
    text: str = ""
    detail: str | None = None


@dataclass(frozen=True)
class FieldProofCommandSurface:
    product_update_recipe: str
    product_update_verify_recipe: str
    apply_smoke_recipe: str
    rollback_smoke_recipe: str
    root_makefile: str
    envelope_schema_version: str
    handoff_schema_version: str
    guest_effect_schema_version: str
    guest_effect_keys: frozenset[str]
    runtime_lifecycle_usage: str
    host_platform_phase_source: str
    prove_usecase_source: str
    prove_composition_source: str
    handoff_policy_source: str
    handoff_contract_source: str
    installed_paths_source: str
    vm_config_makefile: str


@dataclass(frozen=True)
class FieldProofNamedInput:
    name: str
    present: bool
    path_state: str | None = None
    confirm_state: str | None = None


@dataclass(frozen=True)
class FieldProofTrustStoreInput:
    provided: bool
    status: PreflightStatus
    message: str
    detail: str | None = None


@dataclass(frozen=True)
class FieldProofVersionRelationship:
    baseline_helper_version: str | None
    baseline_status: PreflightStatus
    baseline_detail: str | None
    compose_product_version: str | None


@dataclass(frozen=True)
class FieldProofInstalledRuntimeHome:
    product_home: str | None
    makefile_default: str | None
    env_value: str | None


def makefile_target_recipe(makefile: str, target: str) -> str:
    lines = makefile.splitlines()
    start = next(
        index + 1
        for index, line in enumerate(lines)
        if line.startswith(f"{target}:")
        and not line.startswith(f"{target}: override")
        and not line.startswith(f"{target}: export")
    )
    recipe_lines: list[str] = []
    for line in lines[start:]:
        if line.startswith("\t"):
            recipe_lines.append(line.strip())
            continue
        if line:
            break
    return "\n".join(recipe_lines)


def evaluate_field_proof_preflight(
    surface: FieldProofCommandSurface,
    named_inputs: tuple[FieldProofNamedInput, ...],
    trust_store: FieldProofTrustStoreInput,
    source_reads: tuple[FieldProofTextSource, ...] = (),
    version_relationship: FieldProofVersionRelationship | None = None,
    installed_runtime_home: FieldProofInstalledRuntimeHome | None = None,
) -> PreflightReport:
    checks = [
        *[_source_read_check(source) for source in source_reads],
        *_command_surface_checks(surface, source_reads),
        *_named_input_checks(named_inputs),
        _trust_store_check(trust_store),
        _mutating_confirm_check(named_inputs),
    ]
    if version_relationship is not None:
        checks.append(_version_relationship_check(version_relationship))
    if installed_runtime_home is not None:
        checks.extend(_installed_runtime_home_checks(installed_runtime_home))
    return PreflightReport(name="field-proof", checks=tuple(checks))


def product_installed_runtime_home(installed_paths_source: str) -> str | None:
    if DEFAULT_PRODUCT_ROOT_MARKER not in installed_paths_source:
        return None
    product_root = installed_paths_source.split(
        DEFAULT_PRODUCT_ROOT_MARKER, maxsplit=1
    )[1].split('"', maxsplit=1)[0]
    if not product_root.startswith("/") or product_root.endswith("/"):
        return None
    return f"{product_root}/vm"


def makefile_variable_default(makefile: str, name: str) -> str | None:
    prefix = f"{name} ?="
    for line in makefile.splitlines():
        if line.startswith(prefix):
            value = line[len(prefix) :].strip()
            return value or None
    return None


def field_proof_sequence_text() -> str:
    return """Field-proof sequence (cwd: repository root)
  Non-mutating:
    1. make dist/update/field-proof-preflight
    2. provision public trust store with update-bootstrap-trust-store-create
       (private key path stays outside the repo and is never printed)
    3. make dist/dmg/dev
       required: VM_UPDATE_BOOTSTRAP_TRUST_STORE
       artifacts: dist/VitalServerHelper-<releaseLabel>.dmg from release-dev.json
    4. make dist/update/dev && make dist/update/verify/dev
       required: VM_UPDATE_ID, VM_UPDATE_PUBLISHER_KEY_ID,
                 VM_UPDATE_PUBLISHER_PRIVATE_KEY, layer artifacts
       artifacts: dist/update-bundles/<update-id>.tar.gz
  Operator-approved Mac mutations:
    5. make dist/install/dev
       proof: make dist/installed/health
       logs: /Library/Application Support/VitalServerHelper/logs/install.log
       this installs the current release-dev helperVersion, not a later one
    6. make dist/update/dev/apply-smoke
         VM_UPDATE_APPLY_SMOKE_CONFIRM=YES
         VM_UPDATE_APPLY_REQUEST_ID=<unique-request-id>
       pass: prove-update-bootstrap --expect succeeded
       evidence: Host journal, execution report, Runtime Control
                 /platform/operations journal equality, root
                 verify-update-bootstrap receipt vs the product
                 installed VM home and uid/euid=0, persisted handoff
                 guestControlBaseURL vs current Guest address, Host
                 Platform SQLite apply phase journal
       apply-smoke runtime verify-update-bootstrap is required root
                 installed-CLI evidence so prove has its mandatory
                 receipt at InstalledRuntimePaths.defaultInstalled;
                 VM_UPDATE_INSTALLED_RUNTIME_HOME must be that exact
                 product path, not a caller-named home
                 it is not MacPlatformAgent evidence
       not proven: later-than helperVersion, Platform Agent verify
                 field run (TS-220), caller/fresh-run correlation
    7. interruption/restart: TS-192 resume/settle/fail plus TS-226
       Host Platform phase resume (no make target)
    8. make dist/update/dev/rollback-smoke
         VM_UPDATE_APPLY_SMOKE_CONFIRM=YES
         VM_UPDATE_ROLLBACK_PROOF_BUNDLE=<separately-signed-fault-bundle>
       pass: prove-update-bootstrap --expect failed-rolled-back
       apply receipts: container, guest-runtime, host-platform(failed)
       rollback receipts: guest-runtime, container
    9. Recorder -> Guest ingress -> PostgreSQL -> Helper/PWA
       (compose/testkit exist; installed Helper proof is operator-run)
   10. make dist/uninstall/dev VM_UNINSTALL_ARGS=--clean
       log: /private/tmp/tirosh-vitalserver-uninstall.log
Pass/fail: missing, invalid, failed, timeout, and journal mismatch stay
distinct. apply-update-bootstrap exit 0 is handoff admission only.
A later-version upgrade is an operator-chosen identity pair, not a Make proof."""


def field_proof_automation_inventory_text() -> str:
    return """Field-proof automation inventory
  [available] PKG/DMG: make dist/dmg/dev
  [available] signed envelope v2 bundle: make dist/update/dev
  [available] static verify: make dist/update/verify/dev
  [available] installed apply proof: make dist/update/dev/apply-smoke
  [available] Host-failure rollback proof: make dist/update/dev/rollback-smoke
  [unproven] 0.2.2 -> later product version: no later-than comparison exists
  [available] prove-update-bootstrap root verify-update-bootstrap receipt vs product-installed VM home
  [unproven] Platform Agent verify field run (TS-220); caller-owned correlation is required to distinguish MacPlatformAgent from root CLI
  [available] prove-update-bootstrap Guest URL vs current Guest address (TS-221)
  [available] prove-update-bootstrap Host Platform SQLite phases (TS-226)
  [runbook] durable handoff interrupt: resume/settle/fail (TS-192)
  [runbook] Host Platform phase interrupt: manager resume (TS-226)
  [runbook] Recorder/Postgres/Helper/PWA: compose/testkit; no installed target
  [available] clean uninstall: make dist/uninstall/dev (mutating)"""


def _command_surface_checks(
    surface: FieldProofCommandSurface,
    source_reads: tuple[FieldProofTextSource, ...],
) -> list[PreflightCheck]:
    checks: list[PreflightCheck] = []
    if _source_usable(source_reads, SOURCE_PACKAGE_MAKEFILE):
        checks.extend(
            [
                _contains(
                    "product-update-composer",
                    surface.product_update_recipe,
                    "helper-stable-update-release",
                    "product update composes the signed stable bootstrap release",
                ),
                _absent(
                    "product-update-not-schema-3",
                    surface.product_update_recipe,
                    "release-update-bundle",
                    "product update does not use the legacy schema-3 publisher",
                ),
                _contains(
                    "product-update-trust-store",
                    surface.product_update_recipe,
                    "--publisher-trust-store",
                    "product update signs against an explicit publisher trust store",
                ),
                _contains(
                    "product-update-verify",
                    surface.product_update_verify_recipe,
                    "verify-update-bootstrap-bundle",
                    "product update verify uses the bootstrap bundle verifier",
                ),
                _absent(
                    "product-update-verify-not-public-key-flag",
                    surface.product_update_verify_recipe,
                    "--publisher-public-key",
                    "product update verify does not use the retired public-key flag",
                ),
                _contains(
                    "apply-smoke-verify",
                    surface.apply_smoke_recipe,
                    "runtime verify-update-bootstrap",
                    "apply-smoke runs root installed-CLI verify-update-bootstrap so prove has a mandatory receipt",
                ),
                _contains(
                    "apply-smoke-installed-vm-home",
                    surface.apply_smoke_recipe,
                    'VITALSERVER_VM_HOME="$(VM_UPDATE_INSTALLED_RUNTIME_HOME)"',
                    "apply-smoke passes the product installed runtime home variable",
                ),
                _contains(
                    "apply-smoke-bootstrap",
                    surface.apply_smoke_recipe,
                    "runtime apply-update-bootstrap",
                    "apply-smoke launches stable bootstrap apply",
                ),
                _contains(
                    "apply-smoke-proof",
                    surface.apply_smoke_recipe,
                    "runtime prove-update-bootstrap",
                    "apply-smoke proves the Host owner journal",
                ),
                _absent(
                    "apply-smoke-not-legacy-apply-bundle",
                    surface.apply_smoke_recipe,
                    "runtime apply-bundle",
                    "apply-smoke does not call legacy apply-bundle",
                ),
                _contains(
                    "rollback-smoke-proof",
                    surface.rollback_smoke_recipe,
                    "--expect failed-rolled-back",
                    "rollback-smoke proves ordered Host-failure compensation",
                ),
            ]
        )
    if _source_usable(source_reads, SOURCE_ROOT_MAKEFILE):
        checks.extend(
            [
                _contains(
                    "root-apply-smoke-target",
                    surface.root_makefile,
                    "dist/update/dev/apply-smoke",
                    "root Makefile exposes the installed apply proof",
                ),
                _contains(
                    "root-rollback-smoke-target",
                    surface.root_makefile,
                    "dist/update/dev/rollback-smoke",
                    "root Makefile exposes the Host-failure rollback proof",
                ),
                _contains(
                    "root-field-proof-preflight-target",
                    surface.root_makefile,
                    "dist/update/field-proof-preflight",
                    "root Makefile exposes the non-mutating field-proof preflight",
                ),
            ]
        )
    if _source_usable(source_reads, SOURCE_ENVELOPE_POLICY):
        checks.append(
            _equals(
                "envelope-schema",
                surface.envelope_schema_version,
                ENVELOPE_SCHEMA_VERSION,
                f"bootstrap envelope schema is {ENVELOPE_SCHEMA_VERSION}",
            )
        )
    if _source_usable(source_reads, SOURCE_HANDOFF_POLICY):
        checks.append(
            _equals(
                "handoff-schema",
                surface.handoff_schema_version,
                HANDOFF_SCHEMA_VERSION,
                f"handoff schema is {HANDOFF_SCHEMA_VERSION}",
            )
        )
    checks.append(
        _equals(
            "guest-effect-schema",
            surface.guest_effect_schema_version,
            GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA,
            "Guest-owned effect configuration is v2",
        )
    )
    if _source_usable(source_reads, SOURCE_HANDOFF_POLICY) and _source_usable(
        source_reads, SOURCE_HANDOFF_CONTRACT
    ):
        checks.append(_guest_endpoint_ownership(surface))
    if _source_usable(source_reads, SOURCE_RUNTIME_LIFECYCLE):
        checks.extend(_recovery_command_checks(surface.runtime_lifecycle_usage))
    if _source_usable(source_reads, SOURCE_HOST_PLATFORM_CONTRACTS):
        checks.extend(_host_platform_phase_checks(surface.host_platform_phase_source))
    if _source_usable(source_reads, SOURCE_PROVE_USECASE):
        checks.append(_rollback_receipt_order(surface.prove_usecase_source))
        checks.append(
            _contains(
                "prove-guest-control",
                surface.prove_usecase_source,
                "proveGuestControl",
                "prove-update-bootstrap correlates persisted handoff Guest URL",
            )
        )
        checks.append(
            _contains(
                "prove-host-platform",
                surface.prove_usecase_source,
                "proveHostPlatform",
                "prove-update-bootstrap correlates Host Platform SQLite journal",
            )
        )
        checks.append(
            _contains(
                "prove-verification-receipt",
                surface.prove_usecase_source,
                "proveVerificationReceipt",
                "prove-update-bootstrap correlates verify-update-bootstrap receipt",
            )
        )
    if _source_usable(source_reads, SOURCE_PROVE_COMPOSITION):
        checks.append(
            _contains(
                "prove-product-installed-receipt-owner",
                surface.prove_composition_source,
                "InstalledRuntimePaths.defaultInstalled",
                "prove-update-bootstrap reads the product-installed verification receipt owner",
            )
        )
        checks.append(
            _contains(
                "prove-product-installed-receipt-inputs",
                surface.prove_composition_source,
                "installedRootVerificationReceiptProofInputs",
                "prove-update-bootstrap injects product-installed receipt expectations",
            )
        )
    return checks


def _source_usable(
    source_reads: tuple[FieldProofTextSource, ...],
    name: str,
) -> bool:
    matching = [source for source in source_reads if source.name == name]
    if not matching:
        return True
    return matching[0].status == PreflightStatus.PASSED


def _source_read_check(source: FieldProofTextSource) -> PreflightCheck:
    name = f"source-{source.name}"
    if source.status == PreflightStatus.PASSED:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message="source is readable",
        )
    if source.status == PreflightStatus.MISSING:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.MISSING,
            message="source is absent",
            detail=source.detail,
        )
    if source.status == PreflightStatus.INVALID:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="source is invalid",
            detail=source.detail,
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.FAILED,
        message="source read failed",
        detail=source.detail,
    )


def _named_input_checks(
    named_inputs: tuple[FieldProofNamedInput, ...],
) -> list[PreflightCheck]:
    by_name = {item.name: item for item in named_inputs}
    checks: list[PreflightCheck] = []
    for name in COMPOSE_INPUT_NAMES:
        item = by_name.get(name)
        if item is None or not item.present:
            checks.append(
                PreflightCheck(
                    name=name,
                    status=PreflightStatus.MISSING,
                    message="required compose/sign input is unset",
                )
            )
            continue
        if item.path_state is None:
            checks.append(
                PreflightCheck(
                    name=name,
                    status=PreflightStatus.PASSED,
                    message="required compose/sign input is present",
                )
            )
            continue
        checks.append(_path_state_check(name, item.path_state))
    return checks


def _path_state_check(name: str, path_state: str) -> PreflightCheck:
    if path_state == "file":
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message="required path is a regular file",
        )
    if path_state == "missing":
        return PreflightCheck(
            name=name,
            status=PreflightStatus.MISSING,
            message="required path is not a regular file",
        )
    if path_state == "symlink":
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="required path must not be a symlink",
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.FAILED,
        message="required path inspection failed",
        detail=path_state,
    )


def _trust_store_check(
    trust_store: FieldProofTrustStoreInput,
) -> PreflightCheck:
    if not trust_store.provided:
        return PreflightCheck(
            name="update-bootstrap-trust-store",
            status=PreflightStatus.MISSING,
            message="VM_UPDATE_BOOTSTRAP_TRUST_STORE is required",
        )
    return PreflightCheck(
        name="update-bootstrap-trust-store",
        status=trust_store.status,
        message=trust_store.message,
        detail=trust_store.detail,
    )


def _mutating_confirm_check(
    named_inputs: tuple[FieldProofNamedInput, ...],
) -> PreflightCheck:
    confirm = next(
        (item for item in named_inputs if item.name == MUTATING_CONFIRM_INPUT),
        None,
    )
    state = "unset" if confirm is None else (confirm.confirm_state or "unset")
    if state == "yes":
        return PreflightCheck(
            name=MUTATING_CONFIRM_INPUT,
            status=PreflightStatus.PASSED,
            message=("exactly YES; apply/rollback smoke will mutate this Mac"),
        )
    if state == "invalid":
        return PreflightCheck(
            name=MUTATING_CONFIRM_INPUT,
            status=PreflightStatus.INVALID,
            message="mutating confirm must be exactly YES",
        )
    return PreflightCheck(
        name=MUTATING_CONFIRM_INPUT,
        status=PreflightStatus.PASSED,
        message=(
            "unset; mutating apply/rollback smoke stay blocked until "
            "VM_UPDATE_APPLY_SMOKE_CONFIRM=YES"
        ),
    )


def _version_relationship_check(
    relationship: FieldProofVersionRelationship,
) -> PreflightCheck:
    name = "product-version-relationship"
    if relationship.baseline_status != PreflightStatus.PASSED:
        return PreflightCheck(
            name=name,
            status=relationship.baseline_status,
            message="release-dev helperVersion is not available",
            detail=relationship.baseline_detail,
        )
    baseline = relationship.baseline_helper_version
    compose = relationship.compose_product_version
    if compose is None or compose == "":
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=(
                "compose product version is unset; apply-smoke does not prove "
                "a later-version upgrade from helperVersion "
                f"{baseline}"
            ),
        )
    if compose == baseline:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=(
                "compose product version equals release-dev helperVersion "
                f"{baseline}; apply-smoke does not prove a later-version upgrade"
            ),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.PASSED,
        message=(
            "compose product version differs from release-dev helperVersion; "
            "no later-than comparison exists"
        ),
        detail=(f"helperVersion={baseline} VM_UPDATE_PRODUCT_VERSION={compose}"),
    )


def _guest_endpoint_ownership(
    surface: FieldProofCommandSurface,
) -> PreflightCheck:
    if "guestControlBaseURL" in surface.guest_effect_keys:
        return PreflightCheck(
            name="guest-endpoint-ownership",
            status=PreflightStatus.INVALID,
            message=(
                "signed Guest-owned effect configuration must not own "
                "guestControlBaseURL"
            ),
        )
    expected = frozenset(GUEST_OWNER_EFFECT_CONFIGURATION_KEYS)
    if surface.guest_effect_keys != expected:
        return PreflightCheck(
            name="guest-endpoint-ownership",
            status=PreflightStatus.INVALID,
            message="Guest-owned effect configuration keys drifted",
            detail=(
                "missing="
                + ",".join(sorted(expected - surface.guest_effect_keys))
                + " extra="
                + ",".join(sorted(surface.guest_effect_keys - expected))
            ),
        )
    missing_policy = [
        token
        for token in HANDOFF_POLICY_GUEST_ENDPOINT_EVIDENCE
        if token not in surface.handoff_policy_source
    ]
    missing_contract = [
        token
        for token in HANDOFF_CONTRACT_GUEST_ENDPOINT_EVIDENCE
        if token not in surface.handoff_contract_source
    ]
    if missing_policy or missing_contract:
        return PreflightCheck(
            name="guest-endpoint-ownership",
            status=PreflightStatus.MISSING,
            message=(
                "handoff v2 must carry required guestControlBaseURL through "
                "policy constructor and invocation contract"
            ),
            detail=(
                "missing-policy="
                + ",".join(missing_policy)
                + " missing-contract="
                + ",".join(missing_contract)
            ),
        )
    return PreflightCheck(
        name="guest-endpoint-ownership",
        status=PreflightStatus.PASSED,
        message=(
            "Guest Control endpoint is required on handoff v2 invocation and "
            "absent from signed Guest-owned effect configuration"
        ),
    )


def _installed_runtime_home_checks(
    installed_runtime_home: FieldProofInstalledRuntimeHome,
) -> list[PreflightCheck]:
    product_home = installed_runtime_home.product_home
    if product_home is None:
        return [
            PreflightCheck(
                name="installed-runtime-home-contract",
                status=PreflightStatus.MISSING,
                message=(
                    "product installed runtime home is absent from "
                    "InstalledRuntimePaths"
                ),
            )
        ]
    checks = [
        PreflightCheck(
            name="installed-runtime-home-contract",
            status=PreflightStatus.PASSED,
            message="product installed runtime home is InstalledRuntimePaths.defaultInstalled",
            detail=product_home,
        )
    ]
    makefile_default = installed_runtime_home.makefile_default
    if makefile_default is None:
        checks.append(
            PreflightCheck(
                name="installed-runtime-home-makefile",
                status=PreflightStatus.MISSING,
                message=(
                    "VM_UPDATE_INSTALLED_RUNTIME_HOME makefile default is unset"
                ),
            )
        )
    elif makefile_default != product_home:
        checks.append(
            PreflightCheck(
                name="installed-runtime-home-makefile",
                status=PreflightStatus.INVALID,
                message=(
                    "VM_UPDATE_INSTALLED_RUNTIME_HOME makefile default is not "
                    "the product installed runtime home"
                ),
                detail=f"expected={product_home}",
            )
        )
    else:
        checks.append(
            PreflightCheck(
                name="installed-runtime-home-makefile",
                status=PreflightStatus.PASSED,
                message=(
                    "VM_UPDATE_INSTALLED_RUNTIME_HOME makefile default is the "
                    "product installed runtime home"
                ),
            )
        )
    env_value = installed_runtime_home.env_value
    if env_value is None:
        checks.append(
            PreflightCheck(
                name=INSTALLED_RUNTIME_HOME_INPUT,
                status=PreflightStatus.PASSED,
                message=(
                    "VM_UPDATE_INSTALLED_RUNTIME_HOME is unset and the product "
                    "installed runtime home is used"
                ),
            )
        )
    elif env_value != product_home:
        checks.append(
            PreflightCheck(
                name=INSTALLED_RUNTIME_HOME_INPUT,
                status=PreflightStatus.INVALID,
                message=(
                    "VM_UPDATE_INSTALLED_RUNTIME_HOME is not the product "
                    "installed runtime home"
                ),
                detail=f"expected={product_home}",
            )
        )
    else:
        checks.append(
            PreflightCheck(
                name=INSTALLED_RUNTIME_HOME_INPUT,
                status=PreflightStatus.PASSED,
                message=(
                    "VM_UPDATE_INSTALLED_RUNTIME_HOME is the product installed "
                    "runtime home"
                ),
            )
        )
    return checks


def _recovery_command_checks(usage: str) -> list[PreflightCheck]:
    return [
        _contains(
            f"cli-{command}",
            usage,
            command,
            f"installed CLI exposes {command}",
        )
        for command in HANDOFF_RECOVERY_COMMANDS
    ]


def _host_platform_phase_checks(source: str) -> list[PreflightCheck]:
    missing = [phase for phase in HOST_PLATFORM_PHASES if phase not in source]
    if missing:
        return [
            PreflightCheck(
                name="host-platform-phases",
                status=PreflightStatus.MISSING,
                message="durable Host Platform phase machine is incomplete",
                detail="missing=" + ",".join(missing),
            )
        ]
    return [
        PreflightCheck(
            name="host-platform-phases",
            status=PreflightStatus.PASSED,
            message="durable Host Platform phase machine is present",
        )
    ]


def _rollback_receipt_order(source: str) -> PreflightCheck:
    marker = "expectedRollbackLayers"
    if marker not in source:
        return PreflightCheck(
            name="rollback-receipt-order",
            status=PreflightStatus.MISSING,
            message="prove-update-bootstrap does not declare rollback order",
        )
    trailing = source.split(marker, maxsplit=1)[1]
    guest = trailing.find(".guestRuntime")
    container = trailing.find(".container")
    if guest == -1 or container == -1 or guest > container:
        return PreflightCheck(
            name="rollback-receipt-order",
            status=PreflightStatus.INVALID,
            message=(
                "Host-failure rollback receipts must be Guest Runtime then Container"
            ),
        )
    return PreflightCheck(
        name="rollback-receipt-order",
        status=PreflightStatus.PASSED,
        message="Host-failure rollback receipts are Guest Runtime then Container",
    )


def _contains(
    name: str,
    haystack: str,
    needle: str,
    message: str,
) -> PreflightCheck:
    if needle in haystack:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=message,
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.MISSING,
        message=message + f" (missing {needle})",
    )


def _absent(
    name: str,
    haystack: str,
    needle: str,
    message: str,
) -> PreflightCheck:
    if needle in haystack:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message=message + f" (found {needle})",
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.PASSED,
        message=message,
    )


def _equals(
    name: str,
    actual: str,
    expected: str,
    message: str,
) -> PreflightCheck:
    if actual == expected:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=message,
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.INVALID,
        message=message,
        detail=f"actual={actual}",
    )
