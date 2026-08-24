from __future__ import annotations

import os
import plistlib
import subprocess
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle import (
    RuntimeBootstrapAddressReadError,
    probe_guest_runtime_http,
    read_runtime_bootstrap_vm_ip,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    InstalledHealthInput,
    InstalledSmokeInput,
    InstalledStatusInput,
)
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.core.macos_release.settings import (
    MacOSLaunchdTemplateConfig,
    MacOSReleaseSettings,
)

RunProcess = Callable[
    [Sequence[str], Mapping[str, str]],
    subprocess.CompletedProcess[str],
]
LAUNCHD_SERVICE_NOT_FOUND_EXIT_CODE = 113
APP_BUNDLE_PACKAGE_TYPE = "APPL"


@dataclass(frozen=True)
class ProcessObservation:
    exit_code: int | None
    stdout: str
    stderr: str
    execution_failure: str | None

    @property
    def succeeded(self) -> bool:
        return self.execution_failure is None and self.exit_code == 0

    @property
    def failure_reason(self) -> str:
        if self.execution_failure is not None:
            return self.execution_failure
        parts = [f"exitCode={self.exit_code}"]
        if self.stdout.strip():
            parts.append(f"stdout={self.stdout.strip()}")
        if self.stderr.strip():
            parts.append(f"stderr={self.stderr.strip()}")
        return " ".join(parts)


def run_installed_status(input: InstalledStatusInput) -> int:
    settings = load_installed_runtime_settings(input.config)
    status = installed_status(settings)
    return 1 if input.fail_on_unhealthy and status != 0 else 0


def run_installed_health(input: InstalledHealthInput) -> int:
    settings = load_installed_runtime_settings(input.config)
    status = installed_status(settings)
    health = installed_health(settings, input.proxy_port)
    return status or health


def run_installed_smoke(input: InstalledSmokeInput) -> int:
    settings = load_installed_runtime_settings(input.config)
    return installed_smoke(settings, input.proxy_port)


def load_installed_runtime_settings(config: Path) -> MacOSReleaseSettings:
    return load_macos_release_settings(config, repo_root())


def installed_status(
    settings: MacOSReleaseSettings,
    *,
    run_process: RunProcess | None = None,
) -> int:
    product_root = Path(settings.install.product_root)
    vm_home = product_root / "vm"
    status = 0

    print("Installed VM runtime")
    manager_app = Path(settings.install.applications_dir) / f"{settings.app_name}.app"
    if manager_app.is_symlink():
        print(f"  helper app is a symbolic link: {manager_app}")
        status = 1
    elif manager_app.is_dir():
        print(f"  helper app: {manager_app}")
        status |= verify_helper_app_plist(
            manager_app,
            settings.app_name,
            settings.package_identifier,
        )
        manager_executable = manager_app / "Contents/MacOS" / settings.app_name
        if manager_executable.is_file() and os.access(manager_executable, os.X_OK):
            print(f"  helper executable: {manager_executable}")
        else:
            print(f"  missing helper executable: {manager_executable}")
            status = 1
    else:
        print(f"  missing helper app: {manager_app}")
        status = 1

    for label, path in [
        ("launcher", Path(settings.install.vm_cli)),
        ("proxy runner", Path(settings.install.proxy_runner)),
        ("uninstaller", Path(settings.install.uninstaller)),
        (
            "nginx",
            product_root / "host-platform/current/nginx/sbin/nginx",
        ),
    ]:
        if path.is_file() and os.access(path, os.X_OK):
            print(f"  {label}: {path}")
        else:
            print(f"  missing {label}: {path}")
            status = 1

    for label, service_config in [
        ("launchd platform agent", settings.launchd.platform_agent),
        ("launchd vm", settings.launchd.vm),
        ("launchd proxy", settings.launchd.proxy),
        (
            "launchd guest log sync",
            settings.launchd.guest_log_sync,
        ),
        ("launchd watchdog", settings.launchd.watchdog),
    ]:
        status |= print_launchd_status(
            label,
            launchd_service_name(service_config),
            required=True,
            run_process=run_process,
        )

    for label, service_config in [
        (
            "launchd sleep prevention",
            settings.launchd.sleep_prevention,
        ),
        (
            "launchd automatic backup",
            settings.launchd.automatic_backup,
        ),
    ]:
        status |= print_launchd_status(
            label,
            launchd_service_name(service_config),
            required=False,
            run_process=run_process,
        )

    try:
        print(f"  vm ip: {read_runtime_bootstrap_vm_ip(vm_home)}")
    except RuntimeBootstrapAddressReadError as error:
        print(f"  vm ip: unavailable: {error}")
        status = 1

    return status


def verify_helper_app_plist(
    manager_app: Path,
    expected_executable: str,
    expected_bundle_identifier: str,
) -> int:
    """Verify the app bundle Info.plist declares the expected identity contract."""
    info_plist = manager_app / "Contents" / "Info.plist"
    if not info_plist.is_file():
        print(f"  helper app Info.plist: missing: {info_plist}")
        return 1
    try:
        with info_plist.open("rb") as file:
            document = plistlib.load(file)
    except (OSError, plistlib.InvalidFileException, ValueError, TypeError) as error:
        print(f"  helper app Info.plist: decode failed: {info_plist}: {error}")
        return 1
    if not isinstance(document, dict):
        print(f"  helper app Info.plist: invalid root: {info_plist}")
        return 1
    for key, expected in (
        ("CFBundleExecutable", expected_executable),
        ("CFBundleIdentifier", expected_bundle_identifier),
        ("CFBundlePackageType", APP_BUNDLE_PACKAGE_TYPE),
    ):
        status = _verify_plist_string_key(document, key, expected, info_plist)
        if status != 0:
            return status
    print(
        f"  helper executable identity: {document['CFBundleExecutable']} "
        f"bundle: {document['CFBundleIdentifier']}"
    )
    return 0


def _verify_plist_string_key(
    document: Mapping[str, object],
    key: str,
    expected: str,
    info_plist: Path,
) -> int:
    value = document.get(key)
    if value is None:
        print(f"  helper app Info.plist: {key} missing: {info_plist}")
        return 1
    if not isinstance(value, str) or not value:
        print(f"  helper app Info.plist: {key} invalid: {info_plist}")
        return 1
    if value != expected:
        print(
            f"  helper app Info.plist: {key} mismatch "
            f"declared={value} expected={expected}: {info_plist}"
        )
        return 1
    return 0


def installed_health(
    settings: MacOSReleaseSettings,
    proxy_port: str,
    *,
    run_process: RunProcess | None = None,
) -> int:
    product_root = Path(settings.install.product_root)
    vm_home = product_root / "vm"
    status = 0

    try:
        vm_ip = read_runtime_bootstrap_vm_ip(vm_home)
        ok, code = probe_guest_runtime_http(vm_ip)
        if ok:
            print(f"  guest http: ok http://{vm_ip}:80 -> {code}")
        else:
            print(f"  guest http: failed http://{vm_ip}:80 -> {code}")
            status = 1
    except RuntimeBootstrapAddressReadError as error:
        print(f"  guest http: unavailable: {error}")
        status = 1
    status |= print_http_status(
        "host proxy",
        f"http://127.0.0.1:{proxy_port}/",
        run_process=run_process,
    )
    return status


def installed_smoke(
    settings: MacOSReleaseSettings,
    proxy_port: str,
    *,
    run_process: RunProcess | None = None,
) -> int:
    print("Installed runtime smoke")
    status = installed_status(settings, run_process=run_process)
    health = installed_health(
        settings,
        proxy_port,
        run_process=run_process,
    )
    cli_health = installed_cli_health(
        Path(settings.install.vm_cli),
        Path(settings.install.product_root) / "vm",
        run_process=run_process,
    )
    return 1 if any(result != 0 for result in [status, health, cli_health]) else 0


def installed_cli_health(
    vm_cli: Path,
    vm_home: Path,
    *,
    run_process: RunProcess | None = None,
) -> int:
    if not vm_cli.is_file():
        print(f"  installed CLI health: unavailable missing path={vm_cli}")
        return 1
    if not os.access(vm_cli, os.X_OK):
        print(f"  installed CLI health: unavailable not executable path={vm_cli}")
        return 1

    observation = observe_process(
        [str(vm_cli), "runtime", "health"],
        environment={"VITALSERVER_VM_HOME": str(vm_home)},
        run_process=run_process,
    )
    if observation.stdout.strip():
        print(observation.stdout, end=_line_ending(observation.stdout))
    if observation.stderr.strip():
        print(observation.stderr, end=_line_ending(observation.stderr))
    if observation.succeeded:
        print("  installed CLI health: passed exitCode=0")
        return 0
    print(f"  installed CLI health: failed {observation.failure_reason}")
    return 1


def launchd_service_name(config: MacOSLaunchdTemplateConfig) -> str:
    return f"system/{Path(config.installed_plist).stem}"


def print_launchd_status(
    label: str,
    service: str,
    *,
    required: bool,
    run_process: RunProcess | None = None,
) -> int:
    observation = observe_process(
        ["/bin/launchctl", "print", service],
        run_process=run_process,
    )
    if observation.succeeded:
        print(f"  {label}: loaded")
        return 0
    if (
        not required
        and observation.execution_failure is None
        and observation.exit_code == LAUNCHD_SERVICE_NOT_FOUND_EXIT_CODE
    ):
        print(f"  {label}: not loaded (optional): {observation.failure_reason}")
        return 0
    if observation.execution_failure is not None or not required:
        print(f"  {label}: unavailable: {observation.failure_reason}")
        return 1
    print(f"  {label}: not loaded: {observation.failure_reason}")
    return 1


def print_http_status(
    label: str,
    url: str,
    *,
    run_process: RunProcess | None = None,
) -> int:
    observation = observe_process(
        [
            "/usr/bin/curl",
            "-sS",
            "-I",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            "--max-time",
            "5",
            url,
        ],
        run_process=run_process,
    )
    code = observation.stdout.strip() or "curl-error"
    if observation.succeeded and code.isdigit() and 200 <= int(code) < 400:
        print(f"  {label}: ok {url} -> {code}")
        return 0
    print(f"  {label}: failed {url} -> {code}: {observation.failure_reason}")
    return 1


def observe_process(
    command: Sequence[str],
    *,
    environment: Mapping[str, str] | None = None,
    run_process: RunProcess | None = None,
) -> ProcessObservation:
    execute = run_process or run_subprocess
    environment_values = dict(environment or {})
    try:
        result = execute(command, environment_values)
    except OSError as error:
        return ProcessObservation(
            exit_code=None,
            stdout="",
            stderr="",
            execution_failure=f"command execution failed: {error}",
        )
    if not isinstance(result.returncode, int):
        return ProcessObservation(
            exit_code=None,
            stdout="",
            stderr="",
            execution_failure=(
                "process result is invalid: "
                f"returncodeType={type(result.returncode).__name__}"
            ),
        )
    if not isinstance(result.stdout, str) or not isinstance(result.stderr, str):
        return ProcessObservation(
            exit_code=result.returncode,
            stdout="",
            stderr="",
            execution_failure=(
                "process result is invalid: "
                f"stdoutType={type(result.stdout).__name__} "
                f"stderrType={type(result.stderr).__name__}"
            ),
        )
    return ProcessObservation(
        exit_code=result.returncode,
        stdout=result.stdout,
        stderr=result.stderr,
        execution_failure=None,
    )


def run_subprocess(
    command: Sequence[str],
    environment: Mapping[str, str],
) -> subprocess.CompletedProcess[str]:
    process_environment = os.environ.copy()
    process_environment.update(environment)
    return subprocess.run(
        list(command),
        capture_output=True,
        text=True,
        check=False,
        env=process_environment,
    )


def _line_ending(value: str) -> str:
    return "" if value.endswith("\n") else "\n"
