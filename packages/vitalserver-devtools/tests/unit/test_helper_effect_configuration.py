from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_effect_configuration import (
    CONTAINER_LAYER,
    GUEST_OWNER_EFFECT_CONFIGURATION_KEYS,
    GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA,
    GUEST_RUNTIME_LAYER,
    IDENTITY_TRANSITION_KEYS,
    validate_guest_owner_effect_configuration,
    validate_host_platform_effect_configuration,
)


def valid_config(
    layer: str,
    *,
    executor_id: str | None = None,
) -> dict[str, object]:
    if executor_id is None:
        executor_id = f"vitalserver-{layer}-layer-effect-executor-0.2.2"
    return {
        "schemaVersion": GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA,
        "layer": layer,
        "effectExecutorId": executor_id,
        "requestTimeoutSeconds": 60,
        "operationTimeoutSeconds": 900,
        "pollIntervalMilliseconds": 500,
        "apply": {
            "expectedIdentity": f"{layer}-0.2.1",
            "targetIdentity": f"{layer}-0.2.2",
        },
        "rollback": {
            "expectedIdentity": f"{layer}-0.2.2",
            "targetIdentity": f"{layer}-0.2.1",
        },
    }


@pytest.mark.parametrize("layer", [CONTAINER_LAYER, GUEST_RUNTIME_LAYER])
def test_accepts_valid_guest_owner_configuration(layer: str) -> None:
    result = validate_guest_owner_effect_configuration(
        valid_config(layer),
        expected_layer=layer,
        owner=f"{layer} effect configuration",
    )

    assert result.layer == layer
    assert result.effect_executor_id == (
        f"vitalserver-{layer}-layer-effect-executor-0.2.2"
    )
    assert result.request_timeout_seconds == 60
    assert result.operation_timeout_seconds == 900
    assert result.poll_interval_milliseconds == 500
    assert result.apply.expected_identity == f"{layer}-0.2.1"
    assert result.apply.target_identity == f"{layer}-0.2.2"


def test_rejects_non_object() -> None:
    with pytest.raises(DomainError, match="must be an object"):
        validate_guest_owner_effect_configuration(
            "not-an-object",
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_unknown_schema_version() -> None:
    config = valid_config(CONTAINER_LAYER)
    config["schemaVersion"] = "vitalserver.guest-owner-layer-effect-configuration/v1"

    with pytest.raises(DomainError, match="schemaVersion is unsupported"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_wrong_layer() -> None:
    config = valid_config(GUEST_RUNTIME_LAYER)

    with pytest.raises(DomainError, match="layer mismatch"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_missing_required_field() -> None:
    config = valid_config(CONTAINER_LAYER)
    del config["pollIntervalMilliseconds"]

    with pytest.raises(DomainError, match=r"missing=.*pollIntervalMilliseconds"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_extra_field() -> None:
    config = valid_config(CONTAINER_LAYER)
    config["guestControlBaseURL"] = "http://127.0.0.1:18330/"

    with pytest.raises(DomainError, match=r"unknown=.*guestControlBaseURL"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_empty_effect_executor_id() -> None:
    config = valid_config(CONTAINER_LAYER)
    config["effectExecutorId"] = ""

    with pytest.raises(DomainError, match="effectExecutorId must be a non-empty"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


@pytest.mark.parametrize(
    "executor_id",
    [
        "not a valid identifier!",
        "vitalserver/container",
        "x" * 129,
    ],
)
def test_rejects_effect_executor_id_outside_specification_identifier_contract(
    executor_id: str,
) -> None:
    config = valid_config(CONTAINER_LAYER, executor_id=executor_id)

    with pytest.raises(DomainError, match="not a stable ASCII identifier"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_accepts_effect_executor_id_within_identifier_contract() -> None:
    config = valid_config(
        CONTAINER_LAYER,
        executor_id="vitalserver.container-0.2.2_executor",
    )

    result = validate_guest_owner_effect_configuration(
        config,
        expected_layer=CONTAINER_LAYER,
        owner="container effect configuration",
    )

    assert result.effect_executor_id == "vitalserver.container-0.2.2_executor"


@pytest.mark.parametrize("value", [0, -1, 900.5, "60", True, None])
def test_rejects_invalid_request_timeout(value: object) -> None:
    config = valid_config(CONTAINER_LAYER)
    config["requestTimeoutSeconds"] = value

    with pytest.raises(DomainError, match="requestTimeoutSeconds must be"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


@pytest.mark.parametrize("value", [0, 3600.5, "900", True])
def test_rejects_invalid_operation_timeout(value: object) -> None:
    config = valid_config(CONTAINER_LAYER)
    config["operationTimeoutSeconds"] = value

    with pytest.raises(DomainError, match="operationTimeoutSeconds must be"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


@pytest.mark.parametrize("value", [49, 5001, 500.5, True, "500"])
def test_rejects_invalid_poll_interval(value: object) -> None:
    config = valid_config(CONTAINER_LAYER)
    config["pollIntervalMilliseconds"] = value

    with pytest.raises(DomainError, match="pollIntervalMilliseconds must be"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_transition_missing_identity() -> None:
    config = valid_config(CONTAINER_LAYER)
    config["apply"] = {"expectedIdentity": "container-0.2.1"}

    with pytest.raises(DomainError, match="apply fields differ"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_transition_empty_identity() -> None:
    config = valid_config(CONTAINER_LAYER)
    config["apply"] = {
        "expectedIdentity": "",
        "targetIdentity": "container-0.2.2",
    }

    with pytest.raises(DomainError, match=r"expectedIdentity must be a non-empty"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_apply_with_identical_identities() -> None:
    config = valid_config(CONTAINER_LAYER)
    config["apply"] = {
        "expectedIdentity": "container-0.2.2",
        "targetIdentity": "container-0.2.2",
    }

    with pytest.raises(DomainError, match="apply must transition between distinct"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_rejects_rollback_that_does_not_reverse_apply() -> None:
    config = valid_config(CONTAINER_LAYER)
    config["rollback"] = {
        "expectedIdentity": "container-0.2.1",
        "targetIdentity": "container-0.2.2",
    }

    with pytest.raises(DomainError, match="rollback must reverse"):
        validate_guest_owner_effect_configuration(
            config,
            expected_layer=CONTAINER_LAYER,
            owner="container effect configuration",
        )


def test_accepts_valid_host_platform_configuration() -> None:
    executor_id = validate_host_platform_effect_configuration(
        {
            "schemaVersion": "vitalserver.host-platform-layer-effect-configuration/v1",
            "effectExecutorId": "vitalserver-host-platform-layer-effect-executor-0.2.2",
        },
        owner="host-platform effect configuration",
    )

    assert executor_id == ("vitalserver-host-platform-layer-effect-executor-0.2.2")


def test_rejects_host_platform_configuration_missing_executor_id() -> None:
    with pytest.raises(DomainError, match="effectExecutorId must be a non-empty"):
        validate_host_platform_effect_configuration(
            {
                "schemaVersion": (
                    "vitalserver.host-platform-layer-effect-configuration/v1"
                ),
                "effectExecutorId": "",
            },
            owner="host-platform effect configuration",
        )


REPO_ROOT = Path(__file__).resolve().parents[4]
SCHEMAS_ROOT = (
    REPO_ROOT / "apps/vitalserver-macos-runtime/Support/UpdateExecutors/Schemas"
)
EXAMPLES_ROOT = (
    REPO_ROOT / "apps/vitalserver-macos-runtime/Support/UpdateExecutors/Examples"
)


@pytest.mark.parametrize(
    ("schema_file", "example_file", "layer"),
    [
        (
            "container-layer-effect-configuration.schema.json",
            "container-effect-configuration.json",
            CONTAINER_LAYER,
        ),
        (
            "guest-runtime-layer-effect-configuration.schema.json",
            "guest-runtime-effect-configuration.json",
            GUEST_RUNTIME_LAYER,
        ),
    ],
)
def test_validator_stays_in_parity_with_json_schema(
    schema_file: str,
    example_file: str,
    layer: str,
) -> None:
    schema = json.loads((SCHEMAS_ROOT / schema_file).read_text(encoding="utf-8"))

    properties = schema["properties"]
    assert properties["schemaVersion"]["const"] == (
        GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA
    )
    assert properties["layer"]["const"] == layer
    assert set(schema["required"]) == set(GUEST_OWNER_EFFECT_CONFIGURATION_KEYS)
    assert set(properties.keys()) == set(GUEST_OWNER_EFFECT_CONFIGURATION_KEYS)

    transition = schema["$defs"]["identityTransition"]
    assert set(transition["required"]) == set(IDENTITY_TRANSITION_KEYS)
    assert set(transition["properties"].keys()) == set(IDENTITY_TRANSITION_KEYS)

    example = json.loads((EXAMPLES_ROOT / example_file).read_text(encoding="utf-8"))
    result = validate_guest_owner_effect_configuration(
        example,
        expected_layer=layer,
        owner=f"{layer} effect configuration",
    )
    assert result.effect_executor_id == example["effectExecutorId"]
