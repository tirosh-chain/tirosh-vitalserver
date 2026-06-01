from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_guest_tools.domain.errors import GuestContractError
from tirosh_guest_tools.runtime.config import load_config


def valid_runtime_config() -> dict[str, object]:
    return {
        "adminPassword": "admin",
        "publicHost": "",
        "publicPort": 80,
        "redisBackupRetentionCount": 30,
        "redisHost": "redis",
        "redisPort": 6379,
        "testkitEnabled": True,
        "trustProxy": True,
        "vitalFilesDirectory": "/mnt/tirosh-vital-files",
    }


def write_config(path: Path, document: dict[str, object]) -> None:
    path.write_text(json.dumps(document), encoding="utf-8")


def test_load_config_requires_host_owned_fields(tmp_path: Path) -> None:
    config_path = tmp_path / "runtime-config.json"
    document = valid_runtime_config()
    del document["testkitEnabled"]
    write_config(config_path, document)

    with pytest.raises(GuestContractError, match="testkitEnabled") as error:
        load_config(config_path)
    assert error.value.code == "runtime-config-field-missing"


def test_load_config_rejects_invalid_runtime_contract_type(tmp_path: Path) -> None:
    config_path = tmp_path / "runtime-config.json"
    document = valid_runtime_config()
    document["redisPort"] = "6379"
    write_config(config_path, document)

    with pytest.raises(GuestContractError, match="redisPort") as error:
        load_config(config_path)
    assert error.value.code == "runtime-config-field-type-invalid"


def test_load_config_returns_explicit_contract_values(tmp_path: Path) -> None:
    config_path = tmp_path / "runtime-config.json"
    write_config(config_path, valid_runtime_config())

    config = load_config(config_path)

    assert config.redis_host == "redis"
    assert config.redis_backup_retention_count == 30
    assert config.testkit_enabled is True
