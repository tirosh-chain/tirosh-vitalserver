from __future__ import annotations

import subprocess
from collections.abc import Callable, Mapping, Sequence
from dataclasses import replace
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import installed_runtime
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import InstalledSmokeInput
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)

RunProcess = Callable[
    [Sequence[str], Mapping[str, str]],
    subprocess.CompletedProcess[str],
]


def completed(
    command: Sequence[str],
    *,
    returncode: int = 0,
    stdout: str = "",
    stderr: str = "",
) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(
        args=list(command),
        returncode=returncode,
        stdout=stdout,
        stderr=stderr,
    )


def installed_settings(tmp_path: Path):
    root = repo_root()
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    product_root = tmp_path / "Library/Application Support/VitalServerHelper"
    install = replace(
        settings.install,
        product_root=str(product_root),
        applications_dir=str(tmp_path / "Applications"),
        vm_cli=str(tmp_path / "usr/local/bin/vitalserver-vm"),
        proxy_runner=str(tmp_path / "usr/local/bin/vitalserver-proxy-run"),
        uninstaller=str(tmp_path / "usr/local/bin/tirosh-vitalserver-uninstall"),
    )
    return replace(settings, install=install)


def stage_installed_files(settings) -> None:
    helper_app = Path(settings.install.applications_dir) / f"{settings.app_name}.app"
    helper_app.mkdir(parents=True)
    helper_executable = helper_app / "Contents/MacOS" / settings.app_name
    executable_paths = [
        helper_executable,
        Path(settings.install.vm_cli),
        Path(settings.install.proxy_runner),
        Path(settings.install.uninstaller),
        Path(settings.install.product_root) / "nginx/sbin/nginx",
    ]
    for path in executable_paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/sh\n", encoding="utf-8")
        path.chmod(0o755)
    vm_ip_file = Path(settings.install.product_root) / "vm/data/run/vm-ip"
    vm_ip_file.parent.mkdir(parents=True, exist_ok=True)
    vm_ip_file.write_text("192.0.2.10\n", encoding="utf-8")


def launchd_runner(
    *,
    failed_services: frozenset[str] = frozenset(),
) -> tuple[RunProcess, list[list[str]]]:
    commands: list[list[str]] = []

    def run(
        command: Sequence[str],
        environment: Mapping[str, str],
    ) -> subprocess.CompletedProcess[str]:
        command = list(command)
        commands.append(command)
        assert environment == {}
        assert command[:2] == ["/bin/launchctl", "print"]
        service = command[2]
        if service in failed_services:
            return completed(
                command,
                returncode=113,
                stderr=f"Could not find service {service}",
            )
        return completed(command)

    return run, commands


def test_installed_status_requires_helper_app_and_platform_agent(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    settings = installed_settings(tmp_path)
    stage_installed_files(settings)
    optional_services = frozenset(
        {
            "system/ai.tirosh.vitalserver.helper.sleep-prevention",
            "system/ai.tirosh.vitalserver.helper.automatic-backup",
        }
    )
    run_process, commands = launchd_runner(failed_services=optional_services)

    result = installed_runtime.installed_status(
        settings,
        run_process=run_process,
    )

    assert result == 0
    assert [
        "/bin/launchctl",
        "print",
        "system/ai.tirosh.vitalserver.helper.platform-agent",
    ] in commands
    assert [
        "/bin/launchctl",
        "print",
        "system/ai.tirosh.vitalserver.helper.automatic-backup",
    ] in commands
    output = capsys.readouterr().out
    assert "launchd automatic backup: not loaded (optional)" in output
    assert "exitCode=113" in output


def test_installed_status_fails_when_helper_app_is_missing(
    tmp_path: Path,
) -> None:
    settings = installed_settings(tmp_path)
    stage_installed_files(settings)
    helper_app = Path(settings.install.applications_dir) / f"{settings.app_name}.app"
    helper_executable = helper_app / "Contents/MacOS" / settings.app_name
    helper_executable.unlink()
    helper_executable.parent.rmdir()
    helper_executable.parent.parent.rmdir()
    helper_app.rmdir()
    run_process, _ = launchd_runner()

    result = installed_runtime.installed_status(
        settings,
        run_process=run_process,
    )

    assert result == 1


def test_installed_status_fails_when_helper_main_executable_is_missing(
    tmp_path: Path,
) -> None:
    settings = installed_settings(tmp_path)
    stage_installed_files(settings)
    helper_executable = (
        Path(settings.install.applications_dir)
        / f"{settings.app_name}.app"
        / "Contents/MacOS"
        / settings.app_name
    )
    helper_executable.unlink()
    run_process, _ = launchd_runner()

    result = installed_runtime.installed_status(
        settings,
        run_process=run_process,
    )

    assert result == 1


def test_installed_status_fails_when_platform_agent_is_not_loaded(
    tmp_path: Path,
) -> None:
    settings = installed_settings(tmp_path)
    stage_installed_files(settings)
    run_process, _ = launchd_runner(
        failed_services=frozenset(
            {"system/ai.tirosh.vitalserver.helper.platform-agent"}
        )
    )

    result = installed_runtime.installed_status(
        settings,
        run_process=run_process,
    )

    assert result == 1


def test_optional_launchd_execution_failure_is_not_treated_as_disabled(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    settings = installed_settings(tmp_path)
    stage_installed_files(settings)

    def run(
        command: Sequence[str],
        environment: Mapping[str, str],
    ) -> subprocess.CompletedProcess[str]:
        service = list(command)[2]
        if service == "system/ai.tirosh.vitalserver.helper.automatic-backup":
            raise PermissionError("launchctl read not permitted")
        return completed(command)

    result = installed_runtime.installed_status(
        settings,
        run_process=run,
    )

    assert result == 1
    output = capsys.readouterr().out
    assert "launchd automatic backup: unavailable" in output
    assert "command execution failed" in output


def test_optional_launchd_unexpected_exit_is_failure(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    settings = installed_settings(tmp_path)
    stage_installed_files(settings)

    def run(
        command: Sequence[str],
        environment: Mapping[str, str],
    ) -> subprocess.CompletedProcess[str]:
        service = list(command)[2]
        if service == "system/ai.tirosh.vitalserver.helper.automatic-backup":
            return completed(command, returncode=77, stderr="launchctl read failed")
        return completed(command)

    result = installed_runtime.installed_status(
        settings,
        run_process=run,
    )

    assert result == 1
    output = capsys.readouterr().out
    assert "launchd automatic backup: unavailable" in output
    assert "exitCode=77" in output


def test_installed_cli_health_executes_installed_cli_with_installed_vm_home(
    tmp_path: Path,
) -> None:
    vm_cli = tmp_path / "usr/local/bin/vitalserver-vm"
    vm_home = tmp_path / "Library/Application Support/VitalServerHelper/vm"
    vm_cli.parent.mkdir(parents=True)
    vm_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    vm_cli.chmod(0o755)
    requests: list[tuple[list[str], dict[str, str]]] = []

    def run(
        command: Sequence[str],
        environment: Mapping[str, str],
    ) -> subprocess.CompletedProcess[str]:
        requests.append((list(command), dict(environment)))
        return completed(command, stdout="runtime health check passed\n")

    result = installed_runtime.installed_cli_health(
        vm_cli,
        vm_home,
        run_process=run,
    )

    assert result == 0
    assert requests == [
        (
            [str(vm_cli), "runtime", "health"],
            {"VITALSERVER_VM_HOME": str(vm_home)},
        )
    ]


def test_installed_cli_health_missing_executable_is_failure_without_execution(
    tmp_path: Path,
) -> None:
    executed = False

    def run(
        command: Sequence[str],
        environment: Mapping[str, str],
    ) -> subprocess.CompletedProcess[str]:
        nonlocal executed
        executed = True
        return completed(command)

    result = installed_runtime.installed_cli_health(
        tmp_path / "missing-vitalserver-vm",
        tmp_path / "vm",
        run_process=run,
    )

    assert result == 1
    assert executed is False


@pytest.mark.parametrize(
    ("run_process", "expected_text"),
    [
        (
            lambda command, environment: completed(
                command,
                returncode=7,
                stderr="runtime health check failed\n",
            ),
            "exitCode=7",
        ),
        (
            lambda command, environment: (_ for _ in ()).throw(
                PermissionError("not permitted")
            ),
            "command execution failed",
        ),
    ],
)
def test_installed_cli_health_preserves_execution_failure(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
    run_process: RunProcess,
    expected_text: str,
) -> None:
    vm_cli = tmp_path / "vitalserver-vm"
    vm_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    vm_cli.chmod(0o755)

    result = installed_runtime.installed_cli_health(
        vm_cli,
        tmp_path / "vm",
        run_process=run_process,
    )

    assert result == 1
    assert expected_text in capsys.readouterr().out


def test_installed_smoke_adds_installed_cli_health_as_required_proof(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = installed_settings(tmp_path)
    calls: list[str] = []

    def status(*args, **kwargs) -> int:
        calls.append("status")
        return 0

    def health(*args, **kwargs) -> int:
        calls.append("http-health")
        return 0

    def cli_health(*args, **kwargs) -> int:
        calls.append("installed-cli-health")
        return 1

    monkeypatch.setattr(installed_runtime, "installed_status", status)
    monkeypatch.setattr(installed_runtime, "installed_health", health)
    monkeypatch.setattr(installed_runtime, "installed_cli_health", cli_health)

    result = installed_runtime.installed_smoke(settings, "80")

    assert result == 1
    assert calls == ["status", "http-health", "installed-cli-health"]


def test_installed_smoke_does_not_convert_config_read_failure_to_success(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def read_failed(config: Path):
        raise PermissionError(f"cannot read {config}")

    monkeypatch.setattr(
        installed_runtime,
        "load_installed_runtime_settings",
        read_failed,
    )

    with pytest.raises(PermissionError, match="cannot read"):
        installed_runtime.run_installed_smoke(
            InstalledSmokeInput(
                config=tmp_path / "unreadable.toml",
                proxy_port="80",
            )
        )
