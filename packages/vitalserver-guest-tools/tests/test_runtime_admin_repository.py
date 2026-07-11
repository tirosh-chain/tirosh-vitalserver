from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.runtime_admin import FileRuntimeAdminRepository
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.runtime_admin import (
    RuntimeAdminPasswordContractError,
    validated_admin_password,
)


def test_runtime_admin_repository_replaces_only_password_atomically(
    tmp_path: Path,
) -> None:
    path = tmp_path / "runtime-config.json"
    path.write_text(
        json.dumps({"adminPassword": "old", "publicHost": "vitalserver.local"}),
        encoding="utf-8",
    )

    FileRuntimeAdminRepository(path).replace_admin_password("new-secret")

    document = json.loads(path.read_text(encoding="utf-8"))
    assert document == {
        "adminPassword": "new-secret",
        "publicHost": "vitalserver.local",
    }
    assert path.stat().st_mode & 0o777 == 0o600


def test_runtime_admin_repository_preserves_missing_and_invalid_config(
    tmp_path: Path,
) -> None:
    with pytest.raises(GuestControlDependencyError) as missing:
        FileRuntimeAdminRepository(tmp_path / "missing.json").replace_admin_password(
            "new-secret"
        )
    assert missing.value.kind == "runtimeConfigMissing"

    invalid = tmp_path / "invalid.json"
    invalid.write_text("{}", encoding="utf-8")
    with pytest.raises(GuestControlDependencyError) as invalid_error:
        FileRuntimeAdminRepository(invalid).replace_admin_password("new-secret")
    assert invalid_error.value.kind == "runtimeConfigInvalid"


def test_runtime_admin_password_contract_rejects_empty_and_newline() -> None:
    for value in ("", "secret\nvalue", "secret\rvalue", None):
        with pytest.raises(RuntimeAdminPasswordContractError):
            validated_admin_password(value)
