from __future__ import annotations

from tirosh_guest_tools.domain.runtime_observation import ProbeError


def append_probe_error(
    probe_errors: list[ProbeError],
    source: str,
    error: object,
) -> None:
    probe_errors.append(ProbeError(source=source, message=str(error)))
