"""Public exception model for vitalserver-testkit."""

from tirosh_vitalserver.testkit.errors.base import (
    DomainError,
    TestKitError,
    TestKitValueError,
)
from tirosh_vitalserver.testkit.errors.bed import (
    BedCountInvalidError,
    BedDomainError,
    BedRoomNameEmptyError,
    BedRoomNameRequiredError,
    DuplicateBedRoomNameError,
    InsufficientBedsForRecordersError,
)
from tirosh_vitalserver.testkit.errors.recorder import (
    RecorderCountInvalidError,
    RecorderDomainError,
    RecorderPayloadRoomsRequiredError,
)
from tirosh_vitalserver.testkit.errors.vital_file import (
    InvalidVitalFilenameError,
    VitalFileDomainError,
)

__all__ = [
    "BedCountInvalidError",
    "BedDomainError",
    "BedRoomNameEmptyError",
    "BedRoomNameRequiredError",
    "DomainError",
    "DuplicateBedRoomNameError",
    "InsufficientBedsForRecordersError",
    "InvalidVitalFilenameError",
    "RecorderCountInvalidError",
    "RecorderDomainError",
    "RecorderPayloadRoomsRequiredError",
    "TestKitError",
    "TestKitValueError",
    "VitalFileDomainError",
]
