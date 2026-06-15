from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class PreflightStatus(StrEnum):
    PASSED = "passed"
    MISSING = "missing"
    INVALID = "invalid"
    UNAVAILABLE = "unavailable"
    BLOCKED = "blocked"
    FAILED = "failed"


@dataclass(frozen=True)
class PreflightCheck:
    name: str
    status: PreflightStatus
    message: str
    detail: str | None = None

    @property
    def blocks(self) -> bool:
        return self.status != PreflightStatus.PASSED


@dataclass(frozen=True)
class PreflightReport:
    name: str
    checks: tuple[PreflightCheck, ...]

    @property
    def blockers(self) -> tuple[PreflightCheck, ...]:
        return tuple(check for check in self.checks if check.blocks)

    @property
    def passed(self) -> bool:
        return not self.blockers


def print_preflight_report(report: PreflightReport) -> None:
    print(f"Preflight: {report.name}")
    for check in report.checks:
        print(f"  [{check.status}] {check.name}: {check.message}")
        if check.detail:
            print(f"    {check.detail}")
    if report.passed:
        print("Preflight passed.")
        return
    print("Preflight failed:")
    for blocker in report.blockers:
        print(f"  [{blocker.status}] {blocker.name}: {blocker.message}")
        if blocker.detail:
            print(f"    {blocker.detail}")
