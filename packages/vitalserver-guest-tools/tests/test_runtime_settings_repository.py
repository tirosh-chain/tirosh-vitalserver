from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.runtime_settings import (
    FileRuntimeSettingsRepository,
)
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.runtime_settings import (
    RuntimeSettingsContractError,
    validated_runtime_settings,
)


def test_runtime_settings_repository_round_trips_validated_owner_document(
    tmp_path: Path,
) -> None:
    path = tmp_path / "runtime-settings.json"
    source = settings_document()
    path.write_text(json.dumps(source), encoding="utf-8")
    repository = FileRuntimeSettingsRepository(path)

    loaded = repository.read()
    loaded["publicPort"] = 8080
    repository.save(loaded)

    assert repository.read()["publicPort"] == 8080
    assert path.stat().st_mode & 0o777 == 0o600


def test_runtime_settings_repository_preserves_missing_and_invalid(
    tmp_path: Path,
) -> None:
    repository = FileRuntimeSettingsRepository(tmp_path / "missing.json")
    with pytest.raises(GuestControlDependencyError) as missing:
        repository.read()
    assert missing.value.kind == "runtimeSettingsMissing"

    invalid_path = tmp_path / "invalid.json"
    invalid_path.write_text("{}", encoding="utf-8")
    with pytest.raises(GuestControlDependencyError) as invalid:
        FileRuntimeSettingsRepository(invalid_path).read()
    assert invalid.value.kind == "runtimeSettingsInvalid"


def test_runtime_settings_contract_rejects_invalid_adaptive_range() -> None:
    source = settings_document()
    source["recorderIngress"]["sendDataReplayAdaptiveMinConcurrency"] = 9

    with pytest.raises(RuntimeSettingsContractError):
        validated_runtime_settings(source)


def settings_document() -> dict[str, object]:
    path = (
        Path(__file__).parents[3]
        / "apps/vitalserver-platform-agent/packaging/linux/runtime-settings.json"
    )
    return json.loads(path.read_text(encoding="utf-8"))
