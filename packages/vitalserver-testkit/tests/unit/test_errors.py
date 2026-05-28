from __future__ import annotations

from tirosh_vitalserver.testkit.errors import (
    ActiveBedAssignmentsExistError,
    BedAlreadyAssignedError,
    BedDomainError,
    BedNotRegisteredError,
    DomainError,
    InsufficientBedsForRecordersError,
    InvalidVitalFilenameError,
    RecorderCountInvalidError,
    RecorderDomainError,
    VitalFileDomainError,
)
from tirosh_vitalserver.testkit.errors import (
    TestKitError as BaseTestKitError,
)


def test_domain_errors_are_importable_from_errors_package() -> None:
    assert issubclass(BedDomainError, DomainError)
    assert issubclass(RecorderDomainError, DomainError)
    assert issubclass(VitalFileDomainError, DomainError)
    assert issubclass(ActiveBedAssignmentsExistError, BedDomainError)
    assert issubclass(BedAlreadyAssignedError, BedDomainError)
    assert issubclass(BedNotRegisteredError, BedDomainError)
    assert issubclass(InsufficientBedsForRecordersError, BedDomainError)
    assert issubclass(RecorderCountInvalidError, RecorderDomainError)
    assert issubclass(InvalidVitalFilenameError, VitalFileDomainError)
    assert issubclass(DomainError, BaseTestKitError)
    assert issubclass(DomainError, ValueError)
