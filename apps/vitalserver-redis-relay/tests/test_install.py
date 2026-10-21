from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from types import ModuleType

import pytest

APP_DIR = Path(__file__).resolve().parents[1]
PACKAGING = APP_DIR / "packaging"
SCRIPT = PACKAGING / "install.py"
REPO_ROOT = Path(__file__).resolve().parents[3]
OPERATIONS = REPO_ROOT / "docs/redis-relay/operations.md"
LAUNCHD_PLIST = PACKAGING / "macos/ai.tirosh.vitalserver.redis-relay.plist"
SYSTEMD_UNIT = PACKAGING / "linux/vitalserver-redis-relay.service"
WINDOWS_TASK = PACKAGING / "windows/vitalserver-redis-relay-task.xml"


def load_install_script() -> ModuleType:
    spec = importlib.util.spec_from_file_location("redis_relay_install", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def install_script() -> ModuleType:
    return load_install_script()


def test_help_uses_uv_and_does_not_register_a_windows_service() -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--help"],
        capture_output=True,
        text=True,
        check=True,
    )
    collapsed = " ".join(result.stdout.split())
    assert "uv" in collapsed
    assert "launchd" in collapsed
    assert "systemd" in collapsed
    assert "Task Scheduler" in collapsed
    assert "does not register a Windows Service" in collapsed


def test_script_does_not_reimplement_config_or_account_creation() -> None:
    source = SCRIPT.read_text(encoding="utf-8")
    assert "tomllib" not in source
    assert "urlparse" not in source
    assert "dscl" not in source
    assert "useradd" not in source
    assert "uv venv" not in source
    assert '"--no-deps"' in source
    assert "powershell" not in source.lower()
    assert '"--help"' not in source


def test_layouts_match_supervisor_files(install_script: ModuleType) -> None:
    darwin = install_script.layout_for("darwin")
    linux = install_script.layout_for("linux")
    windows = install_script.layout_for("win32")
    plist = LAUNCHD_PLIST.read_text(encoding="utf-8")
    unit = SYSTEMD_UNIT.read_text(encoding="utf-8")
    task = WINDOWS_TASK.read_text(encoding="utf-8")
    assert darwin.executable in plist
    assert linux.executable in unit
    assert windows.executable in task
    assert windows.config_path in task
    assert windows.status_path in task
    assert windows.service_user is None
    assert "S-1-5-19" in task
    assert "password" not in task.lower()
    with pytest.raises(install_script.UnsupportedPlatform):
        install_script.layout_for("freebsd")


def test_wheel_install_is_uv_with_no_deps(install_script: ModuleType) -> None:
    layout = install_script.layout_for("darwin")
    assert install_script.venv_command(layout) == ("uv", "venv", layout.venv)
    assert install_script.wheel_install_command(layout, "/dist/relay.whl") == (
        "uv",
        "pip",
        "install",
        "--python",
        layout.python,
        "--no-deps",
        "/dist/relay.whl",
    )
    windows = install_script.layout_for("win32")
    windows_install = install_script.wheel_install_command(windows, "relay.whl")
    assert windows_install[4] == windows.python
    assert windows.python.endswith("Scripts\\python.exe")
    assert install_script.install_needs_uv(venv_exists=False, wheel_provided=True)
    assert install_script.install_needs_uv(venv_exists=True, wheel_provided=True)
    assert not install_script.install_needs_uv(venv_exists=True, wheel_provided=False)


def test_wheel_and_account_refusals_are_explicit(
    install_script: ModuleType,
    tmp_path: Path,
) -> None:
    assert (
        install_script.wheel_refusal(None, venv_exists=False)
        == "wheel is required when the system venv does not exist"
    )
    assert install_script.wheel_refusal(None, venv_exists=True) is None
    bad_wheel = tmp_path / "other.whl"
    bad_wheel.write_bytes(b"not-a-wheel")
    bad_name = install_script.wheel_refusal(bad_wheel, venv_exists=True)
    assert bad_name is not None
    assert bad_name.startswith("wheel name must match")
    assert (
        install_script.uv_refusal(need_uv=True, uv_on_path=False)
        == "uv is required and was not found on PATH"
    )
    assert install_script.uv_refusal(need_uv=False, uv_on_path=False) is None
    assert (
        install_script.account_refusal(
            user_exists=False,
            group_exists=True,
            user="_vitalserver-redis-relay",
            group="_vitalserver-redis-relay",
        )
        == "service user does not exist: _vitalserver-redis-relay"
    )


def test_destination_state_preserves_a_file_and_rejects_a_symlink(
    install_script: ModuleType,
    tmp_path: Path,
) -> None:
    dest = tmp_path / "redis-relay.toml"
    dest.write_text("enabled = false\n", encoding="utf-8")
    assert install_script.destination_state(dest, replace=False) == "preserved"
    assert dest.read_text(encoding="utf-8") == "enabled = false\n"
    assert install_script.destination_state(dest, replace=True) == "write"
    link = tmp_path / "link.toml"
    link.symlink_to(dest)
    with pytest.raises(install_script.InstallError, match="symlink"):
        install_script.destination_state(link, replace=False)
    directory = tmp_path / "blocked"
    directory.mkdir()
    with pytest.raises(install_script.InstallError, match="not a file"):
        install_script.destination_state(directory, replace=True)


def test_windows_supervisor_command_is_task_scheduler(
    install_script: ModuleType,
) -> None:
    layout = install_script.layout_for("win32")
    command = install_script.windows_register_command(layout, replace=False)
    assert command[:4] == ("schtasks", "/Create", "/TN", layout.supervisor_name)
    assert "sc.exe" not in command
    assert "/F" not in command
    replaced = install_script.windows_register_command(layout, replace=True)
    assert replaced[-1] == "/F"
    query = install_script.windows_query_command(layout)
    assert query == ("schtasks", "/Query", "/TN", layout.supervisor_name)
    delete = install_script.windows_delete_command(layout)
    assert delete[:4] == ("schtasks", "/Delete", "/TN", layout.supervisor_name)
    assert delete[-1] == "/F"
    end = install_script.windows_end_command(layout)
    assert end[:4] == ("schtasks", "/End", "/TN", layout.supervisor_name)
    action = install_script.windows_supervisor_action
    assert action(file_exists=False, task_registered=False, replace=False) == (
        "write",
        False,
    )
    assert action(file_exists=True, task_registered=False, replace=False) == (
        "register",
        False,
    )
    assert action(file_exists=True, task_registered=True, replace=False) == (
        "preserve",
        False,
    )
    assert action(file_exists=True, task_registered=True, replace=True) == (
        "write",
        True,
    )
    assert action(file_exists=False, task_registered=True, replace=False) == (
        "write",
        True,
    )
    acl = "\n".join(
        " ".join(item) for item in install_script.windows_acl_commands(layout)
    )
    assert "*S-1-5-19" in acl
    assert layout.secrets_dir in acl
    encoded = install_script.task_xml_bytes('<Task encoding="UTF-8"></Task>')
    assert encoded.startswith((b"\xff\xfe", b"\xfe\xff"))
    assert "UTF-16" in encoded.decode("utf-16")


def test_operations_document_uv_install_and_windows_paths() -> None:
    operations = " ".join(OPERATIONS.read_text(encoding="utf-8").split())
    module = load_install_script()
    windows = module.layout_for("win32")
    assert "install.py" in operations
    assert "install_native.py" not in operations
    assert "--no-deps" in operations
    assert "uv tool install" in operations
    assert windows.executable in operations
    assert windows.config_path in operations
    assert windows.status_path in operations
    assert windows.secrets_dir in operations
    assert "S-1-5-19" in operations
    assert "Task Scheduler" in operations
    assert "Windows Service(SCM)" in operations
    assert "schtasks /Delete" in operations
    assert "uv pip install --python <venv python> --no-deps <wheel>" in operations
