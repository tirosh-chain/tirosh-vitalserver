from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from types import ModuleType

import pytest


ROOT = Path(__file__).resolve().parents[4]
SCRIPT = ROOT / "apps/vitalserver-platform-agent/packaging/linux/uninstall-linux.py"


@pytest.mark.parametrize("mode", ["standard", "clean"])
def test_linux_uninstall_preserves_or_removes_runtime_data_by_explicit_mode(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, mode: str
) -> None:
    module = load_script()
    opt = tmp_path / "opt/vitalserver"
    etc = tmp_path / "etc/vitalserver"
    var = tmp_path / "var/lib/vitalserver"
    log = tmp_path / "var/log/vitalserver"
    units = tmp_path / "etc/systemd/system"
    external_proof = tmp_path / "var/lib/vitalserver-uninstall-proof"
    current = opt / "current"
    install = var / "install.json"
    provider = etc / "native-runtime-provider.json"
    platform = etc / "platform-agent.json"
    operation = var / "run/platform-workflow.json"
    compose = tmp_path / "usr/bin/docker"
    release = opt / "releases/2.0.0"
    for directory in (release, etc, var / "run", var / "data", log, units, compose.parent):
        directory.mkdir(parents=True, exist_ok=True)
    compose.write_text("#!/bin/sh\n", encoding="utf-8")
    compose.chmod(0o755)
    current.symlink_to("releases/2.0.0")
    write_json(
        install,
        {
            "schemaVersion": 1,
            "state": "installed",
            "platformVersion": "2.0.0",
            "runtimeBundleVersion": "2.3.4",
        },
    )
    write_json(
        release / "release.json",
        {
            "schemaVersion": 1,
            "platformVersion": "2.0.0",
            "runtimeBundleVersion": "2.3.4",
        },
    )
    write_json(
        provider,
        {
            "schemaVersion": 1,
            "composeExecutable": str(compose),
            "composeFile": str(current / "runtime-bundle/compose.yaml"),
            "composeEnvironmentFile": str(etc / "runtime.env"),
            "composeProjectName": "vitalserver",
            "projectDirectory": str(current / "runtime-bundle"),
        },
    )
    write_json(
        platform,
        {
            "schemaVersion": 1,
                "delivery": {
                    "uninstallTool": str(current / "tools/uninstall-linux.py"),
                    "supportExportTool": str(
                        current / "tools/support-export-linux.py"
                    ),
                    "schedulerKind": "systemd-transient",
                },
        },
    )
    for unit, executable in module.UNITS.items():
        (units / unit).write_text(f"[Service]\nExecStart=/usr/bin/env {executable}\n", encoding="utf-8")
    (var / "data/sentinel").write_text("preserve", encoding="utf-8")
    (etc / "settings").write_text("preserve", encoding="utf-8")
    (log / "runtime.log").write_text("preserve", encoding="utf-8")

    monkeypatch.setattr(module, "OPT_ROOT", opt)
    monkeypatch.setattr(module, "ETC_ROOT", etc)
    monkeypatch.setattr(module, "VAR_ROOT", var)
    monkeypatch.setattr(module, "LOG_ROOT", log)
    monkeypatch.setattr(module, "UNIT_ROOT", units)
    monkeypatch.setattr(module, "EXTERNAL_PROOF_ROOT", external_proof)
    monkeypatch.setattr(module, "INSTALL_DOCUMENT", install)
    monkeypatch.setattr(module, "PROVIDER_CONFIG", provider)
    monkeypatch.setattr(module, "PLATFORM_CONFIG", platform)
    monkeypatch.setattr(module, "CURRENT_LINK", current)
    monkeypatch.setattr(module, "LOCK_PATH", tmp_path / "var/lock/vitalserver.lock")
    monkeypatch.setattr(module.os, "geteuid", lambda: 0)
    monkeypatch.setattr(
        module,
        "parse_args",
        lambda: argparse.Namespace(
            mode=mode, operation_id=f"uninstall-{mode}", operation_document=operation
        ),
    )
    commands: list[list[str]] = []
    monkeypatch.setattr(module, "run", lambda command: commands.append(command))

    assert module.main() == 0
    compose_command = next(command for command in commands if len(command) > 1 and command[1] == "compose")
    assert ("--volumes" in compose_command) is (mode == "clean")
    assert not opt.exists()
    assert not install.exists()
    if mode == "standard":
        assert (var / "data/sentinel").read_text(encoding="utf-8") == "preserve"
        assert (etc / "settings").exists()
        assert (log / "runtime.log").exists()
        assert json.loads(operation.read_text(encoding="utf-8"))["state"] == "completed"
    else:
        assert not var.exists()
        assert not etc.exists()
        assert not log.exists()
        proof = json.loads(
            (external_proof / "linux-uninstall-uninstall-clean.json").read_text(encoding="utf-8")
        )
        assert proof["state"] == "completed"
        assert proof["runtimeDataPreserved"] is False


def load_script() -> ModuleType:
    spec = importlib.util.spec_from_file_location("linux_uninstall", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")
