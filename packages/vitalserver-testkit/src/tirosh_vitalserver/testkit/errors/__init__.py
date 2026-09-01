"""Public exception model for vitalserver-testkit."""

from tirosh_vitalserver.testkit.errors.base import (
    DomainError,
    TestKitError,
    TestKitValueError,
)
from tirosh_vitalserver.testkit.errors.bed import (
    ActiveBedAssignmentsExistError,
    BedAlreadyAssignedError,
    BedCountInvalidError,
    BedDomainError,
    BedNotRegisteredError,
    BedRoomNameEmptyError,
    BedRoomNameRequiredError,
    DuplicateBedRoomNameError,
    InsufficientBedsForRecordersError,
)
from tirosh_vitalserver.testkit.errors.hl7 import (
    Hl7EncodingError,
    Hl7Error,
    Hl7FramingError,
    Hl7ParseError,
    Hl7RequestError,
    Hl7SegmentError,
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
    "ActiveBedAssignmentsExistError",
    "BedAlreadyAssignedError",
    "BedCountInvalidError",
    "BedDomainError",
    "BedNotRegisteredError",
    "BedRoomNameEmptyError",
    "BedRoomNameRequiredError",
    "DomainError",
    "DuplicateBedRoomNameError",
    "Hl7EncodingError",
    "Hl7Error",
    "Hl7FramingError",
    "Hl7ParseError",
    "Hl7RequestError",
    "Hl7SegmentError",
    "InsufficientBedsForRecordersError",
    "InvalidVitalFilenameError",
    "RecorderCountInvalidError",
    "RecorderDomainError",
    "RecorderPayloadRoomsRequiredError",
    "TestKitError",
    "TestKitValueError",
    "VitalFileDomainError",
]
