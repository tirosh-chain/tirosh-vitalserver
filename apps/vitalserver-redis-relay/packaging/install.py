#!/usr/bin/env python3
"""Install the Redis Relay wheel with uv and register the existing supervisor file.

uv creates a missing system venv and installs the wheel with --no-deps. When
the venv already exists, the same pip install updates that venv in place.
This script does not parse TOML, inspect secrets, or create accounts. The
relay process validates its config. The operator creates the Unix service
account.

macOS registers the launchd plist, Linux the systemd unit, and Windows the
Task Scheduler XML. It does not register a Windows Service.
"""

from __future__ import annotations

import argparse
import os
import shlex
import shutil
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath

PACKAGING_DIR = Path(__file__).resolve().parent
CONSOLE_NAME = "vitalserver-redis-relay"
WHEEL_PREFIX = "tirosh_vitalserver_redis_relay-"
LOCAL_SERVICE_SID = "S-1-5-19"
LOCAL_SERVICE_ACE = "*S-1-5-19"
ADMINISTRATORS_ACE = "*S-1-5-32-544"


class InstallError(Exception):
    pass


class UnsupportedPlatform(InstallError):
    pass


@dataclass(frozen=True)
class DirectoryContract:
    path: str
    mode: int | None
    owner: str


@dataclass(frozen=True)
class Layout:
    system: str
    service_user: str | None
    service_group: str | None
    venv: str
    python: str
    executable: str
    config_path: str
    status_path: str
    secrets_dir: str
    log_dir: str | None
    directories: tuple[DirectoryContract, ...]
    example_config: str
    supervisor_template: str
    supervisor_destination: str
    supervisor_name: str


def _darwin_layout() -> Layout:
    root = "/usr/local/libexec/vitalserver-redis-relay"
    etc = "/usr/local/etc/vitalserver"
    var = "/usr/local/var/vitalserver"
    log_dir = "/usr/local/var/log/vitalserver"
    venv = f"{root}/venv"
    return Layout(
        system="darwin",
        service_user="_vitalserver-redis-relay",
        service_group="_vitalserver-redis-relay",
        venv=venv,
        python=f"{venv}/bin/python",
        executable=f"{venv}/bin/{CONSOLE_NAME}",
        config_path=f"{etc}/redis-relay.toml",
        status_path=f"{var}/redis-relay-status.json",
        secrets_dir=f"{etc}/secrets",
        log_dir=log_dir,
        directories=(
            DirectoryContract(root, 0o755, "root"),
            DirectoryContract(etc, 0o755, "root"),
            DirectoryContract(f"{etc}/secrets", 0o750, "service"),
            DirectoryContract(var, 0o755, "service"),
            DirectoryContract(log_dir, 0o755, "service"),
        ),
        example_config="macos/native-redis-relay.example.toml",
        supervisor_template="macos/ai.tirosh.vitalserver.redis-relay.plist",
        supervisor_destination=(
            "/Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist"
        ),
        supervisor_name="ai.tirosh.vitalserver.redis-relay",
    )


def _linux_layout() -> Layout:
    root = "/opt/vitalserver/redis-relay"
    etc = "/etc/vitalserver"
    status_dir = "/var/lib/vitalserver/redis-relay"
    venv = f"{root}/venv"
    return Layout(
        system="linux",
        service_user="vitalserver-redis-relay",
        service_group="vitalserver-redis-relay",
        venv=venv,
        python=f"{venv}/bin/python",
        executable=f"{venv}/bin/{CONSOLE_NAME}",
        config_path=f"{etc}/redis-relay.toml",
        status_path=f"{status_dir}/status.json",
        secrets_dir=f"{etc}/secrets",
        log_dir=None,
        directories=(
            DirectoryContract(root, 0o755, "root"),
            DirectoryContract(etc, 0o755, "root"),
            DirectoryContract(f"{etc}/secrets", 0o750, "service"),
            DirectoryContract(status_dir, 0o755, "service"),
        ),
        example_config="linux/native-redis-relay.example.toml",
        supervisor_template="linux/vitalserver-redis-relay.service",
        supervisor_destination="/etc/systemd/system/vitalserver-redis-relay.service",
        supervisor_name="vitalserver-redis-relay.service",
    )


def _windows_layout() -> Layout:
    root = PureWindowsPath(r"C:\Program Files\VitalServer\redis-relay")
    data = PureWindowsPath(r"C:\ProgramData\VitalServer")
    venv = root / "venv"
    return Layout(
        system="win32",
        service_user=None,
        service_group=None,
        venv=str(venv),
        python=str(venv / "Scripts" / "python.exe"),
        executable=str(venv / "Scripts" / f"{CONSOLE_NAME}.exe"),
        config_path=str(data / "redis-relay.toml"),
        status_path=str(data / "redis-relay" / "status.json"),
        secrets_dir=str(data / "secrets"),
        log_dir=None,
        directories=(
            DirectoryContract(str(root), None, "root"),
            DirectoryContract(str(data), None, "root"),
            DirectoryContract(str(data / "secrets"), None, "service"),
            DirectoryContract(str(data / "redis-relay"), None, "service"),
        ),
        example_config="windows/native-redis-relay.example.toml",
        supervisor_template="windows/vitalserver-redis-relay-task.xml",
        supervisor_destination=str(data / "redis-relay-task.xml"),
        supervisor_name="VitalServer Redis Relay",
    )


def layout_for(system: str) -> Layout:
    if system == "darwin":
        return _darwin_layout()
    if system == "linux":
        return _linux_layout()
    if system == "win32":
        return _windows_layout()
    raise UnsupportedPlatform(f"unsupported platform: {system}")


def venv_command(layout: Layout) -> tuple[str, ...]:
    return ("uv", "venv", layout.venv)


def wheel_install_command(layout: Layout, wheel: str) -> tuple[str, ...]:
    return ("uv", "pip", "install", "--python", layout.python, "--no-deps", wheel)


def install_needs_uv(*, venv_exists: bool, wheel_provided: bool) -> bool:
    return (not venv_exists) or wheel_provided


def account_refusal(
    *,
    user_exists: bool,
    group_exists: bool,
    user: str,
    group: str,
) -> str | None:
    if not user_exists:
        return f"service user does not exist: {user}"
    if not group_exists:
        return f"service group does not exist: {group}"
    return None


def wheel_refusal(wheel: Path | None, *, venv_exists: bool) -> str | None:
    if wheel is None:
        if venv_exists:
            return None
        return "wheel is required when the system venv does not exist"
    if not wheel.is_file():
        return f"wheel file is missing: {wheel}"
    name = wheel.name
    if not (name.startswith(WHEEL_PREFIX) and name.endswith(".whl")):
        return f"wheel name must match {WHEEL_PREFIX}*.whl: {wheel}"
    return None


def uv_refusal(*, need_uv: bool, uv_on_path: bool) -> str | None:
    if not need_uv or uv_on_path:
        return None
    return "uv is required and was not found on PATH"


def existing_venv_refusal(venv: Path) -> str | None:
    if venv.is_symlink():
        return f"venv path is a symlink: {venv}"
    if venv.exists() and not venv.is_dir():
        return f"venv path is not a directory: {venv}"
    return None


def destination_state(dest: Path, *, replace: bool) -> str:
    if dest.is_symlink():
        raise InstallError(f"destination is a symlink: {dest}")
    if dest.exists() and not dest.is_file():
        raise InstallError(f"destination is not a file: {dest}")
    if dest.exists() and not replace:
        return "preserved"
    if dest.parent.is_symlink():
        raise InstallError(f"destination parent is a symlink: {dest.parent}")
    return "write"


def windows_supervisor_action(
    *,
    file_exists: bool,
    task_registered: bool,
    replace: bool,
) -> tuple[str, bool]:
    if replace:
        return ("write", True)
    if file_exists and task_registered:
        return ("preserve", False)
    if file_exists:
        return ("register", False)
    return ("write", task_registered)


def task_xml_bytes(text: str) -> bytes:
    declared = text.replace('encoding="UTF-8"', 'encoding="UTF-16"', 1)
    return declared.encode("utf-16")


def windows_query_command(layout: Layout) -> tuple[str, ...]:
    return ("schtasks", "/Query", "/TN", layout.supervisor_name)


def windows_end_command(layout: Layout) -> tuple[str, ...]:
    return ("schtasks", "/End", "/TN", layout.supervisor_name)


def windows_delete_command(layout: Layout) -> tuple[str, ...]:
    return ("schtasks", "/Delete", "/TN", layout.supervisor_name, "/F")


def windows_register_command(layout: Layout, *, replace: bool) -> tuple[str, ...]:
    command = [
        "schtasks",
        "/Create",
        "/TN",
        layout.supervisor_name,
        "/XML",
        layout.supervisor_destination,
    ]
    if replace:
        command.append("/F")
    return tuple(command)


def windows_acl_commands(layout: Layout) -> tuple[tuple[str, ...], ...]:
    venv_parent = str(PureWindowsPath(layout.venv).parent)
    status_dir = str(PureWindowsPath(layout.status_path).parent)
    data_root = str(PureWindowsPath(layout.config_path).parent)
    return (
        _icacls(venv_parent, "(OI)(CI)RX", traverse=True),
        _icacls(data_root, "(OI)(CI)RX", traverse=False),
        _icacls(layout.secrets_dir, "(OI)(CI)R", traverse=True),
        _icacls(status_dir, "(OI)(CI)M", traverse=True),
        (
            "icacls",
            layout.config_path,
            "/grant:r",
            f"{ADMINISTRATORS_ACE}:F",
            "/grant:r",
            f"{LOCAL_SERVICE_ACE}:R",
        ),
    )


def _icacls(path: str, rights: str, *, traverse: bool) -> tuple[str, ...]:
    command = [
        "icacls",
        path,
        "/grant:r",
        f"{ADMINISTRATORS_ACE}:(OI)(CI)F",
        "/grant:r",
        f"{LOCAL_SERVICE_ACE}:{rights}",
    ]
    if traverse:
        command.append("/T")
    return tuple(command)


def current_is_admin() -> bool:
    geteuid = getattr(os, "geteuid", None)
    if geteuid is not None:
        return bool(geteuid() == 0)
    import ctypes

    shell32 = ctypes.WinDLL("shell32")  # type: ignore[attr-defined]
    shell32.IsUserAnAdmin.restype = ctypes.c_int
    return bool(shell32.IsUserAnAdmin())


def run_command(args: Sequence[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        message = f"command failed ({result.returncode}): {shlex.join(args)}"
        if detail:
            message = f"{message}\n{detail}"
        raise InstallError(message)
    return result


def run_or_print(args: Sequence[str], *, dry_run: bool) -> None:
    print("+", shlex.join(args))
    if not dry_run:
        run_command(args)


def _unix_account_exists(layout: Layout) -> tuple[bool, bool]:
    import grp
    import pwd

    if layout.service_user is None or layout.service_group is None:
        raise InstallError("service account is not defined")
    try:
        pwd.getpwnam(layout.service_user)
        user_exists = True
    except KeyError:
        user_exists = False
    try:
        grp.getgrnam(layout.service_group)
        group_exists = True
    except KeyError:
        group_exists = False
    return user_exists, group_exists


def _unix_ids(layout: Layout) -> tuple[int, int]:
    import grp
    import pwd

    if layout.service_user is None or layout.service_group is None:
        raise InstallError("service account is not defined")
    try:
        user = pwd.getpwnam(layout.service_user)
        group = grp.getgrnam(layout.service_group)
    except KeyError as error:
        raise InstallError(f"service account is missing: {error}") from None
    return int(user.pw_uid), int(group.gr_gid)


def _own(path: Path, *, uid: int, gid: int, mode: int) -> None:
    os.chmod(path, mode)
    os.chown(path, uid, gid)


def _ensure_directories(layout: Layout, *, dry_run: bool) -> None:
    ids = _unix_ids(layout) if layout.system != "win32" else None
    for directory in layout.directories:
        path = Path(directory.path)
        print("+", "mkdir", directory.path)
        if dry_run:
            continue
        if path.is_symlink():
            raise InstallError(f"directory path is a symlink: {directory.path}")
        if path.exists() and not path.is_dir():
            raise InstallError(f"directory path is not a directory: {directory.path}")
        path.mkdir(parents=True, exist_ok=True)
        if ids is None or directory.mode is None:
            continue
        uid, gid = (0, 0) if directory.owner == "root" else ids
        _own(path, uid=uid, gid=gid, mode=directory.mode)


def _install_wheel(
    layout: Layout,
    wheel: Path,
    *,
    create_venv: bool,
    dry_run: bool,
) -> None:
    if create_venv:
        run_or_print(venv_command(layout), dry_run=dry_run)
    run_or_print(wheel_install_command(layout, str(wheel)), dry_run=dry_run)


def _copy_config(layout: Layout, *, dry_run: bool) -> str:
    source = PACKAGING_DIR / layout.example_config
    dest = Path(layout.config_path)
    state = destination_state(dest, replace=False)
    if state == "preserved":
        print("preserved", dest)
        return "preserved"
    print("+", "copy", source, "->", dest)
    if dry_run:
        return "copied"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    if layout.system != "win32":
        _uid, gid = _unix_ids(layout)
        _own(dest, uid=0, gid=gid, mode=0o640)
    return "copied"


def _capture(args: Sequence[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, capture_output=True, text=True, check=False)
    except FileNotFoundError:
        raise InstallError(f"command was not found: {args[0]}") from None


def _windows_task_registered(layout: Layout) -> bool:
    result = _capture(windows_query_command(layout))
    return result.returncode == 0


def _end_windows_task(layout: Layout, *, dry_run: bool) -> None:
    command = windows_end_command(layout)
    print("+", shlex.join(command))
    if dry_run:
        return
    result = _capture(command)
    if result.returncode == 0:
        return
    detail = (result.stderr or result.stdout).strip()
    if detail:
        print(detail, file=sys.stderr)


def _copy_unix_supervisor(layout: Layout, source: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    if layout.system == "darwin":
        import grp

        try:
            wheel_gid = int(grp.getgrnam("wheel").gr_gid)
        except KeyError:
            raise InstallError("wheel group does not exist") from None
        _own(dest, uid=0, gid=wheel_gid, mode=0o644)
        return
    _own(dest, uid=0, gid=0, mode=0o644)


def _write_windows_supervisor(
    layout: Layout,
    source: Path,
    dest: Path,
    *,
    replace: bool,
    dry_run: bool,
) -> str:
    if dest.is_symlink():
        raise InstallError(f"supervisor path is a symlink: {dest}")
    if dest.exists() and not dest.is_file():
        raise InstallError(f"supervisor path is not a file: {dest}")
    action, force = windows_supervisor_action(
        file_exists=dest.is_file(),
        task_registered=_windows_task_registered(layout),
        replace=replace,
    )
    if action == "preserve":
        print("preserved", dest)
        return "preserved"
    if action == "write":
        destination_state(dest, replace=True)
        print("+", "copy", source, "->", dest)
        if not dry_run:
            dest.parent.mkdir(parents=True, exist_ok=True)
            text = source.read_text(encoding="utf-8")
            dest.write_bytes(task_xml_bytes(text))
    run_or_print(windows_register_command(layout, replace=force), dry_run=dry_run)
    return "copied"


def _write_supervisor(layout: Layout, *, replace: bool, dry_run: bool) -> str:
    source = PACKAGING_DIR / layout.supervisor_template
    dest = Path(layout.supervisor_destination)
    if layout.system == "win32":
        return _write_windows_supervisor(
            layout,
            source,
            dest,
            replace=replace,
            dry_run=dry_run,
        )
    state = destination_state(dest, replace=replace)
    if state == "preserved":
        print("preserved", dest)
    else:
        print("+", "copy", source, "->", dest)
        if not dry_run:
            _copy_unix_supervisor(layout, source, dest)
    if layout.system == "linux":
        run_or_print(("systemctl", "daemon-reload"), dry_run=dry_run)
    if state == "preserved":
        return "preserved"
    return "copied"


def _supervisor_loaded(layout: Layout) -> bool:
    if layout.system == "darwin":
        result = subprocess.run(
            ("launchctl", "print", f"system/{layout.supervisor_name}"),
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0
    if layout.system == "linux":
        result = subprocess.run(
            ("systemctl", "is-active", layout.supervisor_name),
            capture_output=True,
            text=True,
            check=False,
        )
        return result.stdout.strip() in {"active", "activating", "reloading"}
    raise InstallError("task registration is reported by schtasks /Query")


def start_supervisor(layout: Layout, *, dry_run: bool) -> None:
    if layout.system == "darwin":
        run_or_print(
            ("launchctl", "bootstrap", "system", layout.supervisor_destination),
            dry_run=dry_run,
        )
        return
    if layout.system == "linux":
        run_or_print(("systemctl", "daemon-reload"), dry_run=dry_run)
        run_or_print(
            ("systemctl", "enable", "--now", layout.supervisor_name),
            dry_run=dry_run,
        )
        return
    run_or_print(("schtasks", "/Run", "/TN", layout.supervisor_name), dry_run=dry_run)


def stop_supervisor(layout: Layout, *, dry_run: bool) -> None:
    if layout.system == "darwin":
        run_or_print(
            ("launchctl", "bootout", f"system/{layout.supervisor_name}"),
            dry_run=dry_run,
        )
        return
    if layout.system == "linux":
        run_or_print(("systemctl", "stop", layout.supervisor_name), dry_run=dry_run)
        return
    _end_windows_task(layout, dry_run=dry_run)


def remove_supervisor(layout: Layout, *, dry_run: bool) -> None:
    dest = Path(layout.supervisor_destination)
    if dest.is_symlink():
        raise InstallError(f"supervisor path is a symlink: {dest}")
    if layout.system == "linux" and dest.is_file():
        run_or_print(("systemctl", "disable", layout.supervisor_name), dry_run=dry_run)
    if layout.system == "win32" and _windows_task_registered(layout):
        _end_windows_task(layout, dry_run=dry_run)
        run_or_print(windows_delete_command(layout), dry_run=dry_run)
    if not dest.exists():
        return
    print("+", "rm", dest)
    if dry_run:
        return
    if not dest.is_file():
        raise InstallError(f"supervisor path is not a file: {dest}")
    dest.unlink()
    if layout.system == "linux":
        run_command(("systemctl", "daemon-reload"))


def remove_venv(layout: Layout, *, dry_run: bool) -> None:
    path = Path(layout.venv)
    refusal = existing_venv_refusal(path)
    if refusal is not None:
        raise InstallError(refusal)
    if not path.exists():
        return
    print("+", "rm", "-r", path)
    if not dry_run:
        shutil.rmtree(path)


def _install_refusals(layout: Layout, wheel: Path | None) -> tuple[str, ...]:
    venv = Path(layout.venv)
    venv_exists = venv.is_dir() and not venv.is_symlink()
    refusals: list[str] = []
    venv_problem = existing_venv_refusal(venv)
    if venv_problem is not None:
        refusals.append(venv_problem)
    if layout.system != "win32" and layout.service_user and layout.service_group:
        user_exists, group_exists = _unix_account_exists(layout)
        account_problem = account_refusal(
            user_exists=user_exists,
            group_exists=group_exists,
            user=layout.service_user,
            group=layout.service_group,
        )
        if account_problem is not None:
            refusals.append(account_problem)
    uv_on_path = shutil.which("uv") is not None
    needs_uv = install_needs_uv(
        venv_exists=venv_exists,
        wheel_provided=wheel is not None,
    )
    uv_problem = uv_refusal(need_uv=needs_uv, uv_on_path=uv_on_path)
    if uv_problem is not None:
        refusals.append(uv_problem)
    wheel_problem = wheel_refusal(wheel, venv_exists=venv_exists)
    if wheel_problem is not None:
        refusals.append(wheel_problem)
    return tuple(refusals)


def command_install(args: argparse.Namespace, layout: Layout) -> int:
    dry_run = bool(args.dry_run)
    wheel = None if args.wheel is None else Path(args.wheel)
    refusals = _install_refusals(layout, wheel)
    if refusals:
        for refusal in refusals:
            print(refusal)
        print("no changes were made")
        return 1
    venv_exists = Path(layout.venv).is_dir()
    _ensure_directories(layout, dry_run=dry_run)
    if wheel is not None:
        _install_wheel(
            layout,
            wheel,
            create_venv=not venv_exists,
            dry_run=dry_run,
        )
    else:
        print("preserved", layout.venv)
    config_result = _copy_config(layout, dry_run=dry_run)
    if config_result == "copied":
        print("example config uses source.host 127.0.0.1")
        print("this script does not write secret values")
    if layout.system == "win32":
        for command in windows_acl_commands(layout):
            run_or_print(command, dry_run=dry_run)
        print(f"Windows account is LocalService {LOCAL_SERVICE_SID}")
        print("Task Scheduler is not a Windows Service")
    _write_supervisor(
        layout,
        replace=bool(args.replace_supervisor),
        dry_run=dry_run,
    )
    if args.start:
        start_supervisor(layout, dry_run=dry_run)
    if dry_run:
        print("dry-run: no changes were made")
    return 0


def command_start(args: argparse.Namespace, layout: Layout) -> int:
    start_supervisor(layout, dry_run=bool(args.dry_run))
    if args.dry_run:
        print("dry-run: no changes were made")
    return 0


def command_uninstall(args: argparse.Namespace, layout: Layout) -> int:
    dry_run = bool(args.dry_run)
    if layout.system != "win32" and _supervisor_loaded(layout):
        stop_supervisor(layout, dry_run=dry_run)
    remove_supervisor(layout, dry_run=dry_run)
    remove_venv(layout, dry_run=dry_run)
    print("preserved", layout.config_path)
    print("preserved", layout.secrets_dir)
    print("preserved", layout.status_path)
    if layout.log_dir is not None:
        print("preserved", layout.log_dir)
    if layout.service_user is not None:
        print("preserved", layout.service_user)
    if dry_run:
        print("dry-run: no changes were made")
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Install the Redis Relay wheel with uv and register its supervisor. "
            "macOS uses launchd, Linux uses systemd, and Windows uses "
            "Task Scheduler. This script does not register a Windows Service."
        )
    )
    commands = parser.add_subparsers(dest="command", required=True)
    install = commands.add_parser(
        "install",
        help="install the wheel with uv and copy supervisor files",
    )
    install.add_argument("--wheel", help="path to the redis relay wheel")
    install.add_argument(
        "--start",
        action="store_true",
        help="start the supervisor after install; the relay validates config",
    )
    install.add_argument(
        "--replace-supervisor",
        action="store_true",
        help="overwrite the supervisor definition without restarting it",
    )
    install.add_argument("--dry-run", action="store_true")
    start = commands.add_parser("start", help="start the supervisor")
    start.add_argument("--dry-run", action="store_true")
    uninstall = commands.add_parser(
        "uninstall",
        help="remove the supervisor and venv; keep config and secrets",
    )
    uninstall.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    if sys.version_info < (3, 12):  # noqa: UP036
        print("Python 3.12 or newer is required", file=sys.stderr)
        return 1
    args = parse_args(argv)
    try:
        layout = layout_for(sys.platform)
    except UnsupportedPlatform as error:
        print(str(error), file=sys.stderr)
        return 1
    if not args.dry_run and not current_is_admin():
        print("administrator privileges are required", file=sys.stderr)
        return 1
    try:
        if args.command == "install":
            return command_install(args, layout)
        if args.command == "start":
            return command_start(args, layout)
        if args.command == "uninstall":
            return command_uninstall(args, layout)
    except InstallError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"unknown command: {args.command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
