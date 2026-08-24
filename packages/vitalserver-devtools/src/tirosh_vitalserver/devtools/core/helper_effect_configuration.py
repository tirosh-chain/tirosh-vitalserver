from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_host_platform_installation import (
    HOST_PLATFORM_EFFECT_CONFIGURATION_SCHEMA,
)

"""Pure validation for Helper layer effect configuration documents.

An effect configuration is a publisher-owned, explicit identity document: it
names the effect executor it belongs to through ``effectExecutorId``. The
release composer adopts that declared identity verbatim as the executor artifact
id in the Product Update Specification instead of recomputing or rewriting it.
This module is the single place that decides whether a configuration is valid
enough to be signed, so the executor identity is validated here against the same
identifier contract the specification enforces.

This module must not depend on the bootstrap bundle implementation: it keeps its
own pure helpers for exact-key and identifier checks.
"""

GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA = (
    "vitalserver.guest-owner-layer-effect-configuration/v2"
)

CONTAINER_LAYER = "container"
GUEST_RUNTIME_LAYER = "guest-runtime"

GUEST_OWNER_EFFECT_CONFIGURATION_KEYS = {
    "schemaVersion",
    "layer",
    "effectExecutorId",
    "requestTimeoutSeconds",
    "operationTimeoutSeconds",
    "pollIntervalMilliseconds",
    "apply",
    "rollback",
}

IDENTITY_TRANSITION_KEYS = {"expectedIdentity", "targetIdentity"}

# Must match the Product Update Specification artifact identifier contract so a
# validated effectExecutorId is always a valid specification artifact id.
EXECUTOR_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


@dataclass(frozen=True)
class GuestOwnerIdentityTransition:
    expected_identity: str
    target_identity: str


@dataclass(frozen=True)
class GuestOwnerEffectConfiguration:
    layer: str
    effect_executor_id: str
    request_timeout_seconds: float
    operation_timeout_seconds: float
    poll_interval_milliseconds: int
    apply: GuestOwnerIdentityTransition
    rollback: GuestOwnerIdentityTransition


def validate_guest_owner_effect_configuration(
    value: dict[str, Any],
    *,
    expected_layer: str,
    owner: str,
) -> GuestOwnerEffectConfiguration:
    if not isinstance(value, dict):
        raise DomainError(f"{owner} must be an object")
    _require_exact_keys(value, GUEST_OWNER_EFFECT_CONFIGURATION_KEYS, owner)
    if value["schemaVersion"] != GUEST_OWNER_EFFECT_CONFIGURATION_SCHEMA:
        raise DomainError(
            f"{owner} schemaVersion is unsupported: {value['schemaVersion']}"
        )
    if value["layer"] != expected_layer:
        raise DomainError(
            f"{owner} layer mismatch expected={expected_layer} actual={value['layer']}"
        )
    effect_executor_id = value["effectExecutorId"]
    if not isinstance(effect_executor_id, str) or not effect_executor_id:
        raise DomainError(f"{owner}.effectExecutorId must be a non-empty string")
    _require_identifier(effect_executor_id, f"{owner}.effectExecutorId")
    request_timeout_seconds = value["requestTimeoutSeconds"]
    if not _is_number(request_timeout_seconds) or not (
        0 < request_timeout_seconds <= 900
    ):
        raise DomainError(f"{owner}.requestTimeoutSeconds must be a number in (0, 900]")
    operation_timeout_seconds = value["operationTimeoutSeconds"]
    if not _is_number(operation_timeout_seconds) or not (
        0 < operation_timeout_seconds <= 3600
    ):
        raise DomainError(
            f"{owner}.operationTimeoutSeconds must be a number in (0, 3600]"
        )
    poll_interval_milliseconds = value["pollIntervalMilliseconds"]
    if (
        not isinstance(poll_interval_milliseconds, int)
        or isinstance(poll_interval_milliseconds, bool)
        or not (50 <= poll_interval_milliseconds <= 5000)
    ):
        raise DomainError(
            f"{owner}.pollIntervalMilliseconds must be an integer in [50, 5000]"
        )
    apply = _identity_transition(value["apply"], f"{owner}.apply")
    rollback = _identity_transition(value["rollback"], f"{owner}.rollback")
    if apply.expected_identity == apply.target_identity:
        raise DomainError(f"{owner}.apply must transition between distinct identities")
    if (
        rollback.expected_identity != apply.target_identity
        or rollback.target_identity != apply.expected_identity
    ):
        raise DomainError(f"{owner}.rollback must reverse {owner}.apply")
    return GuestOwnerEffectConfiguration(
        layer=value["layer"],
        effect_executor_id=effect_executor_id,
        request_timeout_seconds=float(request_timeout_seconds),
        operation_timeout_seconds=float(operation_timeout_seconds),
        poll_interval_milliseconds=poll_interval_milliseconds,
        apply=apply,
        rollback=rollback,
    )


def validate_host_platform_effect_configuration(
    value: dict[str, Any],
    *,
    owner: str,
) -> str:
    if not isinstance(value, dict):
        raise DomainError(f"{owner} must be an object")
    if value.get("schemaVersion") != HOST_PLATFORM_EFFECT_CONFIGURATION_SCHEMA:
        raise DomainError(
            f"{owner} schemaVersion is unsupported: {value.get('schemaVersion')}"
        )
    effect_executor_id = value.get("effectExecutorId")
    if not isinstance(effect_executor_id, str) or not effect_executor_id:
        raise DomainError(f"{owner}.effectExecutorId must be a non-empty string")
    _require_identifier(effect_executor_id, f"{owner}.effectExecutorId")
    return effect_executor_id


def _identity_transition(
    value: object,
    owner: str,
) -> GuestOwnerIdentityTransition:
    if not isinstance(value, dict):
        raise DomainError(f"{owner} must be an object")
    _require_exact_keys(value, IDENTITY_TRANSITION_KEYS, owner)
    expected_identity = value["expectedIdentity"]
    target_identity = value["targetIdentity"]
    if not isinstance(expected_identity, str) or not expected_identity:
        raise DomainError(f"{owner}.expectedIdentity must be a non-empty string")
    if not isinstance(target_identity, str) or not target_identity:
        raise DomainError(f"{owner}.targetIdentity must be a non-empty string")
    return GuestOwnerIdentityTransition(
        expected_identity=expected_identity,
        target_identity=target_identity,
    )


def _require_exact_keys(
    value: dict[str, Any],
    expected: set[str],
    owner: str,
) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unknown = sorted(actual - expected)
        raise DomainError(f"{owner} fields differ: missing={missing} unknown={unknown}")


def _require_identifier(value: object, owner: str) -> None:
    if not isinstance(value, str) or not EXECUTOR_ID_PATTERN.fullmatch(value):
        raise DomainError(f"{owner} is not a stable ASCII identifier: {value}")


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)
