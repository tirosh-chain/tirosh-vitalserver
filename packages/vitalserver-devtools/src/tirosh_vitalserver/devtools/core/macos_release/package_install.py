from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class PackageInstallIntent(StrEnum):
    FRESH = "fresh"
    SAME_VERSION_REPAIR = "same-version-repair"
    UPGRADE = "upgrade"
    DOWNGRADE = "downgrade"


@dataclass(frozen=True)
class NumericPackageVersion:
    raw_value: str

    @classmethod
    def parse(cls, raw_value: str) -> NumericPackageVersion | None:
        components = raw_value.split(".")
        if not raw_value or any(
            not component
            or any(character < "0" or character > "9" for character in component)
            for component in components
        ):
            return None
        return cls(raw_value=raw_value)

    @property
    def components(self) -> tuple[str, ...]:
        return tuple(self.raw_value.split("."))


class PackageReceiptReadStage(StrEnum):
    CATALOG = "catalog"
    INFO = "info"


@dataclass(frozen=True)
class PackageReceiptAbsent:
    identifier: str


@dataclass(frozen=True)
class PackageReceiptPresent:
    identifier: str
    version: NumericPackageVersion


@dataclass(frozen=True)
class PackageReceiptReadFailed:
    identifier: str
    stage: PackageReceiptReadStage
    reason: str


PackageReceiptObservation = (
    PackageReceiptAbsent | PackageReceiptPresent | PackageReceiptReadFailed
)


def classify_package_install_intent(
    installed_version: NumericPackageVersion | None,
    target_version: NumericPackageVersion,
) -> PackageInstallIntent:
    if installed_version is None:
        return PackageInstallIntent.FRESH

    installed = installed_version.components
    target = target_version.components
    component_count = max(len(installed), len(target))
    for index in range(component_count):
        installed_component = installed[index] if index < len(installed) else "0"
        target_component = target[index] if index < len(target) else "0"
        component_order = _compare_numeric_component(
            installed_component,
            target_component,
        )
        if component_order < 0:
            return PackageInstallIntent.UPGRADE
        if component_order > 0:
            return PackageInstallIntent.DOWNGRADE
    return PackageInstallIntent.SAME_VERSION_REPAIR


def _compare_numeric_component(left: str, right: str) -> int:
    normalized_left = left.lstrip("0") or "0"
    normalized_right = right.lstrip("0") or "0"
    if len(normalized_left) < len(normalized_right):
        return -1
    if len(normalized_left) > len(normalized_right):
        return 1
    if normalized_left < normalized_right:
        return -1
    if normalized_left > normalized_right:
        return 1
    return 0
