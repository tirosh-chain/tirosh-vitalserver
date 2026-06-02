from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ProbeError:
    source: str
    message: str

    def as_json(self) -> dict[str, str]:
        return {"source": self.source, "message": self.message}


def append_probe_error(
    probe_errors: list[ProbeError],
    source: str,
    error: object,
) -> None:
    probe_errors.append(ProbeError(source=source, message=str(error)))
