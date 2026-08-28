from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.application.inputs import FieldProofPreflightInput
from tirosh_vitalserver.devtools.application.usecases.field_proof_preflight import (
    field_proof_preflight_report,
    read_field_proof_source,
)
from tirosh_vitalserver.devtools.core.field_proof_preflight import (
    COMPOSE_INPUT_NAMES,
    INSTALLED_RUNTIME_HOME_INPUT,
    MUTATING_CONFIRM_INPUT,
    SOURCE_PACKAGE_MAKEFILE,
    FieldProofCommandSurface,
    FieldProofNamedInput,
    FieldProofTextSource,
    FieldProofTrustStoreInput,
    FieldProofInstalledRuntimeHome,
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
)
from tirosh_vitalserver.devtools.core.preflight import PreflightStatus


def valid_surface(**overrides: object) -> FieldProofCommandSurface:
    values: dict[str, object] = {
        "product_update_recipe": (
            "helper-stable-update-release --publisher-trust-store store.json"
        ),
        "product_update_verify_recipe": (
            "verify-update-bootstrap-bundle --publisher-trust-store store.json"
        ),
        "apply_smoke_recipe": (
            'VITALSERVER_VM_HOME="$(VM_UPDATE_INSTALLED_RUNTIME_HOME)"\n'
            "runtime verify-update-bootstrap\n"
            "runtime apply-update-bootstrap\n"
            "runtime prove-update-bootstrap\n"
            "--expect succeeded"
        ),
        "rollback_smoke_recipe": (
            "verify-update-bootstrap-bundle\n"
            "runtime apply-update-bootstrap\n"
            "runtime prove-update-bootstrap\n"
            "--expect failed-rolled-back"
        ),
        "root_makefile": (
            "dist/update/dev/apply-smoke\n"
            "dist/update/dev/rollback-smoke\n"
            "dist/update/field-proof-preflight\n"
            "dist/uninstall/dev"
        ),
        "envelope_schema_version": "v2",
        "handoff_schema_version": "vitalserver.update-bootstrap-handoff/v2",
        "guest_effect_schema_version": (
            "vitalserver.guest-owner-layer-effect-configuration/v2"
        ),
        "guest_effect_keys": frozenset(GUEST_OWNER_EFFECT_CONFIGURATION_KEYS),
        "runtime_lifecycle_usage": (
            "verify-update-bootstrap\n"
            "apply-update-bootstrap\n"
            "prove-update-bootstrap\n"
            "resume-update-bootstrap-handoff\n"
            "settle-update-bootstrap-handoff\n"
            "fail-update-bootstrap"
        ),
        "host_platform_phase_source": (
            "requested prepared previous-quiesced interfaces-published "
            "target-activated target-services-loaded compensating compensated "
            "completed failed"
        ),
        "prove_usecase_source": (
            "let expectedRollbackLayers: [UpdateLayer] = [\n"
            "    .guestRuntime,\n"
            "    .container,\n"
            "]\n"
            "func proveGuestControl(\n"
            "func proveHostPlatform(\n"
            "func proveVerificationReceipt(\n"
            "func provePlatformAgentVerification(\n"
            "func provePlatformAgentApplySelection(\n"
        ),
        "prove_composition_source": (
            "InstalledRuntimePaths.defaultInstalled\n"
            "installedRootVerificationReceiptProofInputs\n"
            "requirePlatformAgentVerification\n"
        ),
        "installed_paths_source": (
            'defaultProductRoot = URL(fileURLWithPath: '
            '"/Library/Application Support/VitalServerHelper")\n'
        ),
        "vm_config_makefile": (
            "VM_UPDATE_INSTALLED_RUNTIME_HOME ?= "
            "/Library/Application Support/VitalServerHelper/vm\n"
        ),
        "platform_agent_service_source": (
            "SystemPlatformAgentUpdateBootstrapVerificationInvoker(\n"
            "SystemPlatformAgentUpdateBootstrapSelectionOwner(\n"
        ),
        "control_panel_environment_source": (
            "let commandWorker = MacRuntimeControlCommandWorker(\n"
        ),
        "handoff_policy_source": (
            "public static func makeInvocation(\n"
            "    journal: UpdateBootstrapJournal,\n"
            "    guestControlBaseURL: String\n"
            ") throws -> UpdateBootstrapHandoffInvocation {\n"
            "    return UpdateBootstrapHandoffInvocation(\n"
            "        guestControlBaseURL: guestControlBaseURL\n"
            "    )\n"
            "}"
        ),
        "handoff_contract_source": (
            "public let guestControlBaseURL: String\n"
            "case guestControlBaseURL\n"
            "guestControlBaseURL: try container.decode(\n"
            "    String.self,\n"
            "    forKey: .guestControlBaseURL\n"
        ),
    }
    values.update(overrides)
    return FieldProofCommandSurface(**values)  # type: ignore[arg-type]


def present_inputs() -> tuple[FieldProofNamedInput, ...]:
    return tuple(
        FieldProofNamedInput(
            name=name,
            present=True,
            path_state=(
                "file"
                if name
                in {
                    "VM_UPDATE_PUBLISHER_PRIVATE_KEY",
                    "VM_UPDATE_BOOTSTRAP_TRUST_STORE",
                }
                else None
            ),
        )
        for name in COMPOSE_INPUT_NAMES
    )


def valid_trust_store() -> FieldProofTrustStoreInput:
    return FieldProofTrustStoreInput(
        provided=True,
        status=PreflightStatus.PASSED,
        message="update bootstrap trust store is valid v2",
    )


def test_evaluate_passes_the_current_v2_command_surface() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        present_inputs(),
        valid_trust_store(),
    )

    assert report.passed
    assert report.name == "field-proof"


def test_evaluate_rejects_schema_3_product_update_publisher() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(
            product_update_recipe="release-update-bundle --bundle-kind product-update"
        ),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    blocker = next(
        check
        for check in report.blockers
        if check.name == "product-update-not-schema-3"
    )
    assert blocker.status == PreflightStatus.INVALID


def test_evaluate_rejects_envelope_v1() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(envelope_schema_version="v1"),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    blocker = next(
        check for check in report.blockers if check.name == "envelope-schema"
    )
    assert blocker.status == PreflightStatus.INVALID
    assert blocker.detail == "actual=v1"


def test_evaluate_rejects_handoff_v1() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(handoff_schema_version="vitalserver.update-bootstrap-handoff/v1"),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    assert any(check.name == "handoff-schema" for check in report.blockers)


def test_evaluate_rejects_handoff_policy_without_guest_control_url() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(
            handoff_policy_source=(
                "public static let schemaVersion = "
                '"vitalserver.update-bootstrap-handoff/v2"\n'
                "public static func makeInvocation(journal: UpdateBootstrapJournal)"
            )
        ),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    blocker = next(
        check for check in report.blockers if check.name == "guest-endpoint-ownership"
    )
    assert blocker.status == PreflightStatus.MISSING
    assert "guestControlBaseURL: String" in (blocker.detail or "")


def test_evaluate_rejects_handoff_contract_without_guest_control_url() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(
            handoff_contract_source="public struct UpdateBootstrapHandoffInvocation"
        ),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    blocker = next(
        check for check in report.blockers if check.name == "guest-endpoint-ownership"
    )
    assert blocker.status == PreflightStatus.MISSING
    assert "case guestControlBaseURL" in (blocker.detail or "")


def test_evaluate_rejects_signed_guest_endpoint() -> None:
    keys = frozenset({*GUEST_OWNER_EFFECT_CONFIGURATION_KEYS, "guestControlBaseURL"})
    report = evaluate_field_proof_preflight(
        valid_surface(guest_effect_keys=keys),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    blocker = next(
        check for check in report.blockers if check.name == "guest-endpoint-ownership"
    )
    assert blocker.status == PreflightStatus.INVALID


def test_evaluate_preserves_missing_compose_inputs() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        (),
        FieldProofTrustStoreInput(
            provided=False,
            status=PreflightStatus.MISSING,
            message="VM_UPDATE_BOOTSTRAP_TRUST_STORE is required",
        ),
    )

    assert not report.passed
    missing = {
        check.name
        for check in report.blockers
        if check.status == PreflightStatus.MISSING
    }
    assert "VM_UPDATE_ID" in missing
    assert "VM_UPDATE_PUBLISHER_PRIVATE_KEY" in missing
    assert "update-bootstrap-trust-store" in missing


def test_evaluate_does_not_require_mutating_confirm() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        present_inputs(),
        valid_trust_store(),
    )

    confirm = next(
        check
        for check in report.checks
        if check.name == "VM_UPDATE_APPLY_SMOKE_CONFIRM"
    )
    assert confirm.status == PreflightStatus.PASSED
    assert "unset" in confirm.message
    assert "blocked" in confirm.message


def test_evaluate_accepts_exact_yes_mutating_confirm() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        (
            *present_inputs(),
            FieldProofNamedInput(
                name=MUTATING_CONFIRM_INPUT,
                present=True,
                confirm_state="yes",
            ),
        ),
        valid_trust_store(),
    )

    confirm = next(
        check for check in report.checks if check.name == MUTATING_CONFIRM_INPUT
    )
    assert confirm.status == PreflightStatus.PASSED
    assert "exactly YES" in confirm.message
    assert "mutate" in confirm.message


def test_evaluate_rejects_non_yes_mutating_confirm_without_echoing_value() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        (
            *present_inputs(),
            FieldProofNamedInput(
                name=MUTATING_CONFIRM_INPUT,
                present=True,
                confirm_state="invalid",
            ),
        ),
        valid_trust_store(),
    )

    confirm = next(
        check for check in report.blockers if check.name == MUTATING_CONFIRM_INPUT
    )
    assert confirm.status == PreflightStatus.INVALID
    assert confirm.message == "mutating confirm must be exactly YES"
    assert confirm.detail is None
    joined = " ".join(filter(None, (confirm.message, confirm.detail)))
    assert "true" not in joined
    assert "yes" not in joined


def test_evaluate_rejects_host_platform_before_guest_rollback_order() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(
            prove_usecase_source=(
                "let expectedRollbackLayers: [UpdateLayer] = [\n"
                "    .hostPlatform,\n"
                "    .container,\n"
                "    .guestRuntime,\n"
                "]"
            )
        ),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    blocker = next(
        check for check in report.blockers if check.name == "rollback-receipt-order"
    )
    assert blocker.status == PreflightStatus.INVALID


def test_evaluate_requires_guest_url_and_host_platform_proof_methods() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(
            prove_usecase_source=(
                "let expectedRollbackLayers: [UpdateLayer] = [\n"
                "    .guestRuntime,\n"
                "    .container,\n"
                "]"
            )
        ),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    names = {check.name for check in report.blockers}
    assert "prove-guest-control" in names
    assert "prove-host-platform" in names
    assert "prove-verification-receipt" in names


def test_evaluate_skips_recipe_guesses_when_makefile_read_failed() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(product_update_recipe=""),
        present_inputs(),
        valid_trust_store(),
        source_reads=(
            FieldProofTextSource(
                name=SOURCE_PACKAGE_MAKEFILE,
                status=PreflightStatus.FAILED,
                detail="source read failed",
            ),
        ),
    )

    source = next(
        check
        for check in report.blockers
        if check.name == f"source-{SOURCE_PACKAGE_MAKEFILE}"
    )
    assert source.status == PreflightStatus.FAILED
    assert not any(check.name == "product-update-composer" for check in report.checks)


def test_evaluate_reports_absent_source_without_empty_success() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        present_inputs(),
        valid_trust_store(),
        source_reads=(
            FieldProofTextSource(
                name=SOURCE_PACKAGE_MAKEFILE,
                status=PreflightStatus.MISSING,
                detail="source is absent",
            ),
        ),
    )

    source = next(
        check
        for check in report.blockers
        if check.name == f"source-{SOURCE_PACKAGE_MAKEFILE}"
    )
    assert source.status == PreflightStatus.MISSING
    assert not any(check.name == "product-update-composer" for check in report.checks)


def test_read_field_proof_source_preserves_absence(tmp_path: Path) -> None:
    source = read_field_proof_source(tmp_path / "missing.mk", SOURCE_PACKAGE_MAKEFILE)

    assert source.status == PreflightStatus.MISSING
    assert source.text == ""
    assert source.detail == "source is absent"


def test_read_field_proof_source_preserves_read_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    path = tmp_path / "package.mk"
    path.write_text("internal/vm/update:\n", encoding="utf-8")
    original_read_text = Path.read_text

    def fail_read(
        self: Path,
        encoding: str | None = None,
        errors: str | None = None,
    ) -> str:
        if self == path:
            raise PermissionError("permission denied")
        return original_read_text(self, encoding=encoding, errors=errors)

    monkeypatch.setattr(Path, "read_text", fail_read)
    source = read_field_proof_source(path, SOURCE_PACKAGE_MAKEFILE)

    assert source.status == PreflightStatus.FAILED
    assert source.text == ""
    assert source.detail == "source read failed"
    assert "permission denied" not in (source.detail or "")


def test_version_relationship_equal_is_not_a_later_upgrade() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        present_inputs(),
        valid_trust_store(),
        version_relationship=FieldProofVersionRelationship(
            baseline_helper_version="0.2.2",
            baseline_status=PreflightStatus.PASSED,
            baseline_detail=None,
            compose_product_version="0.2.2",
        ),
    )

    relationship = next(
        check for check in report.checks if check.name == "product-version-relationship"
    )
    assert relationship.status == PreflightStatus.PASSED
    assert "does not prove a later-version upgrade" in relationship.message


def test_version_relationship_does_not_rank_different_versions() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        present_inputs(),
        valid_trust_store(),
        version_relationship=FieldProofVersionRelationship(
            baseline_helper_version="0.2.2",
            baseline_status=PreflightStatus.PASSED,
            baseline_detail=None,
            compose_product_version="0.2.3",
        ),
    )

    relationship = next(
        check for check in report.checks if check.name == "product-version-relationship"
    )
    assert relationship.status == PreflightStatus.PASSED
    assert "no later-than comparison exists" in relationship.message
    assert relationship.detail == (
        "helperVersion=0.2.2 VM_UPDATE_PRODUCT_VERSION=0.2.3"
    )


def test_makefile_target_recipe_skips_override_and_export_lines() -> None:
    makefile = (
        "internal/vm/update/dev: override VM_RELEASE_FILE := x\n"
        "internal/vm/update/field-proof-preflight: export "
        "VM_UPDATE_ID := $(VM_UPDATE_ID)\n"
        "internal/vm/update:\n"
        "\thelper-stable-update-release\n"
        "\n"
        "internal/vm/update/verify:\n"
        "\tverify-update-bootstrap-bundle\n"
    )

    assert (
        makefile_target_recipe(makefile, "internal/vm/update")
        == "helper-stable-update-release"
    )


def valid_installed_runtime_home(
    **overrides: object,
) -> FieldProofInstalledRuntimeHome:
    values: dict[str, object] = {
        "product_home": "/Library/Application Support/VitalServerHelper/vm",
        "makefile_default": "/Library/Application Support/VitalServerHelper/vm",
        "env_value": None,
    }
    values.update(overrides)
    return FieldProofInstalledRuntimeHome(**values)  # type: ignore[arg-type]


def test_product_installed_runtime_home_comes_from_default_product_root() -> None:
    source = (
        'public static let defaultProductRoot = URL(fileURLWithPath: '
        '"/Library/Application Support/VitalServerHelper")\n'
        "public static let defaultInstalled = InstalledRuntimePaths("
        "productRoot: defaultProductRoot)\n"
    )
    assert product_installed_runtime_home(source) == (
        "/Library/Application Support/VitalServerHelper/vm"
    )


def test_evaluate_rejects_non_product_installed_runtime_home_override() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        present_inputs(),
        valid_trust_store(),
        installed_runtime_home=valid_installed_runtime_home(
            env_value="/var/root/.tirosh/vitalserver-vm"
        ),
    )

    assert not report.passed
    blocker = next(
        check
        for check in report.blockers
        if check.name == "VM_UPDATE_INSTALLED_RUNTIME_HOME"
    )
    assert blocker.status == PreflightStatus.INVALID
    assert "product installed runtime home" in blocker.message
    assert "/var/root/.tirosh" not in blocker.message


def test_evaluate_accepts_unset_installed_runtime_home_when_makefile_matches() -> None:
    report = evaluate_field_proof_preflight(
        valid_surface(),
        present_inputs(),
        valid_trust_store(),
        installed_runtime_home=valid_installed_runtime_home(),
    )

    assert report.passed
    home = next(
        check
        for check in report.checks
        if check.name == "VM_UPDATE_INSTALLED_RUNTIME_HOME"
    )
    assert home.status == PreflightStatus.PASSED


def test_makefile_variable_default_reads_question_assign() -> None:
    makefile = (
        "VM_UPDATE_INSTALLED_RUNTIME_HOME ?= "
        "/Library/Application Support/VitalServerHelper/vm\n"
    )
    assert makefile_variable_default(
        makefile, "VM_UPDATE_INSTALLED_RUNTIME_HOME"
    ) == "/Library/Application Support/VitalServerHelper/vm"


def test_inventory_keeps_platform_agent_verify_field_run_unproven() -> None:
    inventory = field_proof_automation_inventory_text()
    sequence = field_proof_sequence_text()

    assert "[unproven] Platform Agent verify field run (TS-229)" in inventory
    assert "contract exists, installed MacPlatformAgent run does not" in inventory
    assert "[available] prove-update-bootstrap optional --require-platform-agent-verification" in inventory
    assert "MacPlatformAgent evidence" in sequence
    assert "is not MacPlatformAgent evidence" in sequence
    assert "TS-230" in sequence
    assert "[available] prove-update-bootstrap optional --require-platform-agent-verification journal selection correlation (TS-230)" in inventory
    assert "[unproven] Platform Agent verify-then-apply field run (TS-230)" in inventory
    assert "[available] Platform Agent verify field run" not in inventory


def test_current_repo_command_surface_understands_v2(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    for name in (
        *COMPOSE_INPUT_NAMES,
        MUTATING_CONFIRM_INPUT,
        INSTALLED_RUNTIME_HOME_INPUT,
    ):
        monkeypatch.delenv(name, raising=False)

    report = field_proof_preflight_report(
        FieldProofPreflightInput(update_bootstrap_trust_store=None)
    )
    surface_blockers = [
        check
        for check in report.blockers
        if check.name
        not in {
            *COMPOSE_INPUT_NAMES,
            "update-bootstrap-trust-store",
            "product-version-relationship",
        }
        and not check.name.startswith("source-")
    ]

    assert surface_blockers == []
    assert not report.passed


def test_application_rejects_non_yes_confirm_without_echoing_value(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    for name in (*COMPOSE_INPUT_NAMES, MUTATING_CONFIRM_INPUT):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv(MUTATING_CONFIRM_INPUT, "true")

    report = field_proof_preflight_report(
        FieldProofPreflightInput(update_bootstrap_trust_store=None)
    )
    confirm = next(
        check for check in report.checks if check.name == MUTATING_CONFIRM_INPUT
    )

    assert confirm.status == PreflightStatus.INVALID
    assert confirm.message == "mutating confirm must be exactly YES"
    assert "true" not in confirm.message
    assert confirm.detail is None


def test_cli_exposes_field_proof_preflight_help(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    from tirosh_vitalserver.devtools import cli

    monkeypatch.setattr(
        "sys.argv",
        ["vitalserver-devtools", "field-proof-preflight", "--help"],
    )
    with pytest.raises(SystemExit) as exit_info:
        cli.main()

    assert exit_info.value.code == 0
    captured = capsys.readouterr()
    assert "field-proof-preflight" in captured.out
    assert "--update-bootstrap-trust-store" in captured.out


@pytest.mark.parametrize(
    ("command", "name"),
    [
        ("resume-update-bootstrap-handoff", "cli-resume-update-bootstrap-handoff"),
        ("settle-update-bootstrap-handoff", "cli-settle-update-bootstrap-handoff"),
        ("fail-update-bootstrap", "cli-fail-update-bootstrap"),
    ],
)
def test_evaluate_requires_interruption_recovery_commands(
    command: str,
    name: str,
) -> None:
    usage = valid_surface().runtime_lifecycle_usage.replace(command, "")
    report = evaluate_field_proof_preflight(
        valid_surface(runtime_lifecycle_usage=usage),
        present_inputs(),
        valid_trust_store(),
    )

    assert not report.passed
    assert any(check.name == name for check in report.blockers)
