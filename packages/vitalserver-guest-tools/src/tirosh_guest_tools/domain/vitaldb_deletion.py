from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

LAB_RECORDER_VERSION = "vitalserver-lab"


@dataclass(frozen=True)
class VitalDBDeletionPlan:
    requested_ids: tuple[str, ...]
    lab_vrcodes: frozenset[str]


class VitalDBDeletionPolicyError(Exception):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


def plan_recorder_deletion(
    document: Mapping[str, Any],
    requested_ids: Sequence[str],
) -> VitalDBDeletionPlan:
    targets = _delete_targets(
        document,
        collection="recorders",
        identity_field="vrcode",
        requested_ids=requested_ids,
    )
    return VitalDBDeletionPlan(
        requested_ids=tuple(requested_ids),
        lab_vrcodes=frozenset(
            str(target["vrcode"])
            for target in targets
            if target.get("version") == LAB_RECORDER_VERSION
        ),
    )


def plan_bed_deletion(
    document: Mapping[str, Any],
    requested_ids: Sequence[str],
) -> VitalDBDeletionPlan:
    targets = _delete_targets(
        document,
        collection="beds",
        identity_field="bedID",
        requested_ids=requested_ids,
    )
    return VitalDBDeletionPlan(
        requested_ids=tuple(requested_ids),
        lab_vrcodes=frozenset(
            str(target["vrcode"])
            for target in targets
            if target.get("linkedRecorderVersion") == LAB_RECORDER_VERSION
            and isinstance(target.get("vrcode"), str)
        ),
    )


def _delete_targets(
    document: Mapping[str, Any],
    *,
    collection: str,
    identity_field: str,
    requested_ids: Sequence[str],
) -> list[Mapping[str, Any]]:
    values = document.get(collection)
    if document.get("state") != "loaded" or not isinstance(values, list):
        raise VitalDBDeletionPolicyError(
            f"VitalDB {collection} read model contract is invalid.",
            kind="vitaldb-read-model-invalid",
        )
    requested = set(requested_ids)
    targets: list[Mapping[str, Any]] = []
    for value in values:
        if not isinstance(value, Mapping):
            raise VitalDBDeletionPolicyError(
                f"VitalDB {collection} read model item is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if value.get(identity_field) in requested:
            targets.append(value)
    not_hidden = [
        identity
        for identity in requested_ids
        if any(
            target.get(identity_field) == identity
            and target.get("visibility") != "hidden"
            for target in targets
        )
    ]
    if not_hidden:
        raise VitalDBDeletionPolicyError(
            "VitalDB entity must be hidden before delete: " + ", ".join(not_hidden),
            kind="vitaldb-read-model-delete-not-hidden",
        )
    return targets
