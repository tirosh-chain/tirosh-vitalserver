"""Bed domain helpers."""

from tirosh_vitalserver.testkit.domain.bed.identity import (
    bed_id_for_room,
    beds_for_room_names,
    create_bed,
    create_beds,
    normalize_bed_room_names,
)
from tirosh_vitalserver.testkit.domain.bed.models import (
    Bed,
    BedRecorderAssignment,
)
from tirosh_vitalserver.testkit.domain.bed.rules import (
    require_bed_capacity_for_recorders,
)

__all__ = [
    "Bed",
    "BedRecorderAssignment",
    "bed_id_for_room",
    "beds_for_room_names",
    "create_bed",
    "create_beds",
    "normalize_bed_room_names",
    "require_bed_capacity_for_recorders",
]
