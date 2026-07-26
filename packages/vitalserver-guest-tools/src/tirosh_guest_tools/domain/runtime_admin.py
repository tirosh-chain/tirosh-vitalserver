from __future__ import annotations


class RuntimeAdminPasswordContractError(ValueError):
    pass


def validated_admin_password(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise RuntimeAdminPasswordContractError(
            "runtime admin password must be a non-empty string"
        )
    if "\n" in value or "\r" in value:
        raise RuntimeAdminPasswordContractError(
            "runtime admin password must not contain a newline"
        )
    return value
