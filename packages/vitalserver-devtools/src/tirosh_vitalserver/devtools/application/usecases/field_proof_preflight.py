from __future__ import annotations

import json
import os
import stat
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import FieldProofPreflightInput
from tirosh_vitalserver.devtools.config.update_bootstrap_trust_store import (
    UpdateBootstrapTrustStoreDecodeError,
    UpdateBootstrapTrustStoreInvalidError,
    UpdateBootstrapTrustStoreReadError,
    UpdateBootstrapTrustStoreUnavailableError,
    load_update_bootstrap_trust_store,
)
from tirosh_vitalserver.devtools.core.field_proof_preflight import (
    COMPOSE_INPUT_NAMES,
    MUTATING_CONFIRM_INPUT,
    MUTATING_CONFIRM_REQUIRED_VALUE,
    SECRET_INPUT_NAMES,
    SOURCE_ENVELOPE_POLICY,
    SOURCE_HANDOFF_CONTRACT,
    SOURCE_HANDOFF_POLICY,
    SOURCE_HOST_PLATFORM_CONTRACTS,
    SOURCE_PACKAGE_MAKEFILE,
    SOURCE_INSTALLED_PATHS,
    SOURCE_PROVE_COMPOSITION,
    SOURCE_PROVE_USECASE,
    SOURCE_RELEASE_DEV,
    SOURCE_ROOT_MAKEFILE,
    SOURCE_RUNTIME_LIFECYCLE,
    SOURCE_VM_CONFIG_MAKEFILE,
    FieldProofCommandSurface,
    FieldProofInstalledRuntimeHome,
    FieldProofNamedInput,
    FieldProofTextSource,
    FieldProofTrustStoreInput,
    FieldProofVersionRelationship,
    evaluate_field_proof_preflight,
    field_proof_automation_inventory_text,
    field_proof_sequence_text,
    makefile_target_recipe,
    makefile_variable_default,
    product_installed_runtime_home,
)
from tirosh_vitalserver.devtools.core.helper_effect_configuration import (
    GUEST_OWNER_EFFECT_CONFIGURATION_KEYS,
    GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA,
)
from tirosh_vitalserver.devtools.core.preflight import (
    PreflightReport,
    PreflightStatus,
    print_preflight_report,
)


def run_field_proof_preflight(input: FieldProofPreflightInput) -> int:
    report = field_proof_preflight_report(input)
    print_preflight_report(report)
    print()
    print(field_proof_automation_inventory_text())
    print()
    print(field_proof_sequence_text())
    if report.passed:
        return 0
    raise SystemExit(1)


def field_proof_preflight_report(
    input: FieldProofPreflightInput,
) -> PreflightReport:
    root = repo_root()
    sources = {
        name: read_field_proof_source(root / name, name)
        for name in (
            SOURCE_PACKAGE_MAKEFILE,
            SOURCE_ROOT_MAKEFILE,
            SOURCE_ENVELOPE_POLICY,
            SOURCE_HANDOFF_POLICY,
            SOURCE_HANDOFF_CONTRACT,
            SOURCE_RUNTIME_LIFECYCLE,
            SOURCE_HOST_PLATFORM_CONTRACTS,
            SOURCE_PROVE_USECASE,
            SOURCE_PROVE_COMPOSITION,
            SOURCE_INSTALLED_PATHS,
            SOURCE_VM_CONFIG_MAKEFILE,
            SOURCE_RELEASE_DEV,
        )
    }
    package_makefile = sources[SOURCE_PACKAGE_MAKEFILE]
    root_makefile = sources[SOURCE_ROOT_MAKEFILE]
    envelope_policy = sources[SOURCE_ENVELOPE_POLICY]
    handoff_policy = sources[SOURCE_HANDOFF_POLICY]
    handoff_contract = sources[SOURCE_HANDOFF_CONTRACT]
    runtime_lifecycle = sources[SOURCE_RUNTIME_LIFECYCLE]
    host_platform = sources[SOURCE_HOST_PLATFORM_CONTRACTS]
    prove_usecase = sources[SOURCE_PROVE_USECASE]
    prove_composition = sources[SOURCE_PROVE_COMPOSITION]
    installed_paths = sources[SOURCE_INSTALLED_PATHS]
    vm_config_makefile = sources[SOURCE_VM_CONFIG_MAKEFILE]
    release_dev = sources[SOURCE_RELEASE_DEV]
    named_inputs = tuple(
        _named_input(name, input.update_bootstrap_trust_store)
        for name in (*COMPOSE_INPUT_NAMES, MUTATING_CONFIRM_INPUT)
    )
    compose_raw = os.environ.get("VM_UPDATE_PRODUCT_VERSION")
    compose_product_version = compose_raw if compose_raw else None
    return evaluate_field_proof_preflight(
        FieldProofCommandSurface(
            product_update_recipe=_loaded_recipe(
                package_makefile, "internal/vm/update"
            ),
            product_update_verify_recipe=_loaded_recipe(
                package_makefile, "internal/vm/update/verify"
            ),
            apply_smoke_recipe=_loaded_recipe(
                package_makefile, "internal/vm/update/apply-smoke"
            ),
            rollback_smoke_recipe=_loaded_recipe(
                package_makefile, "internal/vm/update/rollback-smoke/dev"
            ),
            root_makefile=_loaded_text(root_makefile),
            envelope_schema_version=_quoted_assignment(
                _loaded_text(envelope_policy),
                'schemaVersion == "',
            ),
            handoff_schema_version=_quoted_assignment(
                _loaded_text(handoff_policy),
                'schemaVersion = "',
            ),
            guest_effect_schema_version=GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA,
            guest_effect_keys=frozenset(GUEST_OWNER_EFFECT_CONFIGURATION_KEYS),
            runtime_lifecycle_usage=_loaded_text(runtime_lifecycle),
            host_platform_phase_source=_loaded_text(host_platform),
            prove_usecase_source=_loaded_text(prove_usecase),
            prove_composition_source=_loaded_text(prove_composition),
            handoff_policy_source=_loaded_text(handoff_policy),
            handoff_contract_source=_loaded_text(handoff_contract),
            installed_paths_source=_loaded_text(installed_paths),
            vm_config_makefile=_loaded_text(vm_config_makefile),
        ),
        named_inputs,
        _trust_store_input(input.update_bootstrap_trust_store),
        source_reads=tuple(sources.values()),
        version_relationship=_version_relationship(
            release_dev,
            compose_product_version,
        ),
        installed_runtime_home=_installed_runtime_home(
            installed_paths,
            vm_config_makefile,
        ),
    )


def read_field_proof_source(path: Path, name: str) -> FieldProofTextSource:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return FieldProofTextSource(
            name=name,
            status=PreflightStatus.MISSING,
            detail="source is absent",
        )
    except OSError:
        return FieldProofTextSource(
            name=name,
            status=PreflightStatus.FAILED,
            detail="source read failed",
        )
    except UnicodeDecodeError:
        return FieldProofTextSource(
            name=name,
            status=PreflightStatus.INVALID,
            detail="source decode failed",
        )
    return FieldProofTextSource(
        name=name,
        status=PreflightStatus.PASSED,
        text=text,
    )


def _loaded_text(source: FieldProofTextSource) -> str:
    if source.status != PreflightStatus.PASSED:
        return ""
    return source.text


def _loaded_recipe(source: FieldProofTextSource, target: str) -> str:
    if source.status != PreflightStatus.PASSED:
        return ""
    try:
        return makefile_target_recipe(source.text, target)
    except StopIteration:
        return ""


def _quoted_assignment(source: str, marker: str) -> str:
    if marker not in source:
        return "missing"
    return source.split(marker, maxsplit=1)[1].split('"', maxsplit=1)[0]


def _named_input(
    name: str,
    cli_trust_store: Path | None,
) -> FieldProofNamedInput:
    raw = os.environ.get(name)
    if name == MUTATING_CONFIRM_INPUT:
        return _confirm_input(raw)
    if name == "VM_UPDATE_BOOTSTRAP_TRUST_STORE" and cli_trust_store is not None:
        raw = str(cli_trust_store)
    present = bool(raw is not None and raw.strip())
    if name not in SECRET_INPUT_NAMES and name != "VM_UPDATE_BOOTSTRAP_TRUST_STORE":
        return FieldProofNamedInput(name=name, present=present)
    if not present:
        return FieldProofNamedInput(
            name=name,
            present=False,
            path_state="unset",
        )
    return FieldProofNamedInput(
        name=name,
        present=True,
        path_state=_path_state(Path(raw.strip())),
    )


def _confirm_input(raw: str | None) -> FieldProofNamedInput:
    if raw is None or raw == "":
        return FieldProofNamedInput(
            name=MUTATING_CONFIRM_INPUT,
            present=False,
            confirm_state="unset",
        )
    if raw == MUTATING_CONFIRM_REQUIRED_VALUE:
        return FieldProofNamedInput(
            name=MUTATING_CONFIRM_INPUT,
            present=True,
            confirm_state="yes",
        )
    return FieldProofNamedInput(
        name=MUTATING_CONFIRM_INPUT,
        present=True,
        confirm_state="invalid",
    )


def _path_state(path: Path) -> str:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return "missing"
    except OSError:
        return "unreadable"
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISREG(mode):
        return "file"
    return "missing"


def _installed_runtime_home(
    installed_paths: FieldProofTextSource,
    vm_config_makefile: FieldProofTextSource,
) -> FieldProofInstalledRuntimeHome:
    product_home = product_installed_runtime_home(_loaded_text(installed_paths))
    makefile_default = makefile_variable_default(
        _loaded_text(vm_config_makefile),
        "VM_UPDATE_INSTALLED_RUNTIME_HOME",
    )
    raw = os.environ.get("VM_UPDATE_INSTALLED_RUNTIME_HOME")
    env_value = raw.strip() if raw is not None and raw.strip() else None
    if raw is not None and env_value is None:
        env_value = ""
    return FieldProofInstalledRuntimeHome(
        product_home=product_home,
        makefile_default=makefile_default,
        env_value=env_value,
    )


def _version_relationship(
    release_dev: FieldProofTextSource,
    compose_product_version: str | None,
) -> FieldProofVersionRelationship:
    if release_dev.status != PreflightStatus.PASSED:
        return FieldProofVersionRelationship(
            baseline_helper_version=None,
            baseline_status=release_dev.status,
            baseline_detail=release_dev.detail,
            compose_product_version=compose_product_version,
        )
    try:
        document = json.loads(release_dev.text)
    except json.JSONDecodeError:
        return FieldProofVersionRelationship(
            baseline_helper_version=None,
            baseline_status=PreflightStatus.INVALID,
            baseline_detail="release-dev.json decode failed",
            compose_product_version=compose_product_version,
        )
    if not isinstance(document, dict):
        return FieldProofVersionRelationship(
            baseline_helper_version=None,
            baseline_status=PreflightStatus.INVALID,
            baseline_detail="release-dev.json is not an object",
            compose_product_version=compose_product_version,
        )
    helper_version = document.get("helperVersion")
    if not isinstance(helper_version, str) or helper_version == "":
        return FieldProofVersionRelationship(
            baseline_helper_version=None,
            baseline_status=PreflightStatus.MISSING,
            baseline_detail="release-dev.json helperVersion is missing",
            compose_product_version=compose_product_version,
        )
    return FieldProofVersionRelationship(
        baseline_helper_version=helper_version,
        baseline_status=PreflightStatus.PASSED,
        baseline_detail=None,
        compose_product_version=compose_product_version,
    )


def _trust_store_input(cli_path: Path | None) -> FieldProofTrustStoreInput:
    raw = os.environ.get("VM_UPDATE_BOOTSTRAP_TRUST_STORE")
    path = cli_path
    if path is None and raw and raw.strip():
        path = Path(raw.strip())
    if path is None:
        return FieldProofTrustStoreInput(
            provided=False,
            status=PreflightStatus.MISSING,
            message="VM_UPDATE_BOOTSTRAP_TRUST_STORE is required",
        )
    try:
        load_update_bootstrap_trust_store(path)
    except UpdateBootstrapTrustStoreUnavailableError:
        return FieldProofTrustStoreInput(
            provided=True,
            status=PreflightStatus.MISSING,
            message="update bootstrap trust store is unavailable",
        )
    except UpdateBootstrapTrustStoreReadError:
        return FieldProofTrustStoreInput(
            provided=True,
            status=PreflightStatus.FAILED,
            message="update bootstrap trust store read failed",
        )
    except UpdateBootstrapTrustStoreDecodeError:
        return FieldProofTrustStoreInput(
            provided=True,
            status=PreflightStatus.INVALID,
            message="update bootstrap trust store decode failed",
        )
    except UpdateBootstrapTrustStoreInvalidError:
        return FieldProofTrustStoreInput(
            provided=True,
            status=PreflightStatus.INVALID,
            message="update bootstrap trust store is invalid",
        )
    return FieldProofTrustStoreInput(
        provided=True,
        status=PreflightStatus.PASSED,
        message="update bootstrap trust store is valid v2",
    )
