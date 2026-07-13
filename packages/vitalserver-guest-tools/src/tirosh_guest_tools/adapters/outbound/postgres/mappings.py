from __future__ import annotations

from typing import Any

from tirosh_guest_tools.domain.guest_control.models import VitalDBReadModelDependencyError


def domain_document(value: object, *, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise VitalDBReadModelDependencyError(
            f"VitalDB {label} document is not an object.",
            kind="vitaldb-read-model-invalid",
        )
    return dict(value)
