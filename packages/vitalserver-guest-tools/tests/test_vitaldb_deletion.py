from __future__ import annotations

import pytest

from tirosh_guest_tools.domain.vitaldb_deletion import (
    VitalDBDeletionPolicyError,
    plan_bed_deletion,
    plan_recorder_deletion,
)


def test_recorder_delete_plan_uses_explicit_lab_version_and_vrcode() -> None:
    plan = plan_recorder_deletion(
        {
            "state": "loaded",
            "recorders": [
                {
                    "vrcode": "LAB-001",
                    "version": "vitalserver-lab",
                    "visibility": "hidden",
                },
                {
                    "vrcode": "VR-002",
                    "version": "1.0",
                    "visibility": "hidden",
                },
            ],
        },
        ["LAB-001", "VR-002"],
    )

    assert plan.requested_ids == ("LAB-001", "VR-002")
    assert plan.lab_vrcodes == frozenset({"LAB-001"})


def test_bed_delete_plan_uses_explicit_linked_lab_recorder() -> None:
    plan = plan_bed_deletion(
        {
            "state": "loaded",
            "beds": [
                {
                    "bedID": "bed-1",
                    "vrcode": "LAB-001",
                    "linkedRecorderVersion": "vitalserver-lab",
                    "visibility": "hidden",
                }
            ],
        },
        ["bed-1"],
    )

    assert plan.lab_vrcodes == frozenset({"LAB-001"})


def test_delete_plan_rejects_visible_target_before_side_effects() -> None:
    with pytest.raises(VitalDBDeletionPolicyError) as error:
        plan_recorder_deletion(
            {
                "state": "loaded",
                "recorders": [
                    {
                        "vrcode": "LAB-001",
                        "version": "vitalserver-lab",
                        "visibility": "visible",
                    }
                ],
            },
            ["LAB-001"],
        )

    assert error.value.kind == "vitaldb-read-model-delete-not-hidden"
