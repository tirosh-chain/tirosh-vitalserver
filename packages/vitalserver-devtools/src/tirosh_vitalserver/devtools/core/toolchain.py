from __future__ import annotations

from collections.abc import Iterable

from tirosh_vitalserver.devtools.core.errors import DomainError


def normalize_compression_threads(value: int | None, default: int) -> int:
    if value is not None:
        return max(1, value)
    return max(1, default)


def parse_compression_threads(value: str) -> int:
    try:
        return max(1, int(value))
    except ValueError as exc:
        raise DomainError(
            "error: VITALSERVER_VM_COMPRESSION_THREADS must be an integer"
        ) from exc


def require_branch_match(expected: str, actual: str) -> None:
    if actual != expected:
        raise DomainError(
            "release artifacts must be built from branch "
            f"'{expected}' (current: {actual})"
        )


def parse_template_variables(raw_values: Iterable[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_value in raw_values:
        key, separator, value = raw_value.partition("=")
        if not separator or not key:
            raise DomainError(f"error: invalid --var value: {raw_value}")
        if key in values:
            raise DomainError(f"error: duplicate template variable: {key}")
        values[key] = value
    return values


def render_token_template(content: str, values: dict[str, str]) -> str:
    rendered = content
    for key, value in values.items():
        rendered = rendered.replace("${" + key + "}", value)
    return rendered
