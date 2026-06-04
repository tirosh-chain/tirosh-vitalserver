import json

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle import (
    wait_for_runtime_stopped,
)
from tirosh_vitalserver.devtools.application.inputs import RuntimeWaitInput


def test_wait_for_runtime_stopped_accepts_stopped_lifecycle(tmp_path):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")

    result = wait_for_runtime_stopped(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    assert result == 0


def test_wait_for_runtime_stopped_rejects_stopping_lifecycle(tmp_path):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopping"}), encoding="utf-8")

    with pytest.raises(SystemExit, match="timed out waiting for VM lifecycle stopped"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
            )
        )
