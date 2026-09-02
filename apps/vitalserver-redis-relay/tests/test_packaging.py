from __future__ import annotations

import json
import signal
import subprocess
import time
import tomllib
import zipfile
from collections.abc import Iterator
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
OPERATIONS = REPO_ROOT / "docs/redis-relay/operations.md"
PYPROJECT = APP_DIR / "pyproject.toml"
DOCKERFILE = APP_DIR / "Dockerfile"
LAUNCHD_PLIST = APP_DIR / "packaging/macos/ai.tirosh.vitalserver.redis-relay.plist"
SYSTEMD_UNIT = APP_DIR / "packaging/linux/vitalserver-redis-relay.service"
MACOS_EXAMPLE_TOML = APP_DIR / "packaging/macos/native-redis-relay.example.toml"
LINUX_EXAMPLE_TOML = APP_DIR / "packaging/linux/native-redis-relay.example.toml"
DUPLICATE_DRAFT = REPO_ROOT / "packages/vitalserver-redis-relay"
CONSOLE_NAME = "vitalserver-redis-relay"


def supervisor_contract_from_operations() -> dict[str, dict[str, str]]:
    rows: dict[str, dict[str, str]] = {}
    in_table = False
    for line in OPERATIONS.read_text(encoding="utf-8").splitlines():
        if line.startswith("| OS | system venv | supervisor executable |"):
            in_table = True
            continue
        if in_table and line.startswith("|---"):
            continue
        if in_table and line.startswith("|"):
            cells = [part.strip().strip("`") for part in line.split("|")[1:4]]
            os_name, venv, executable = cells
            rows[os_name] = {"venv": venv, "executable": executable}
            continue
        if in_table:
            break
    return rows


def launchd_program_arguments(text: str) -> list[str]:
    start = text.index("<key>ProgramArguments</key>")
    block = text[start:]
    block = block[block.index("<array>") : block.index("</array>")]
    return [
        line.split("<string>", 1)[1].split("</string>", 1)[0]
        for line in block.splitlines()
        if "<string>" in line
    ]


def operations_path_row(path: str) -> tuple[str, str]:
    for line in OPERATIONS.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| `") or path not in line:
            continue
        cells = [part.strip().strip("`") for part in line.split("|")[1:6]]
        if cells[0] == path:
            return cells[2], cells[3]
    raise AssertionError(f"operations path table is missing {path}")


def systemd_exec_start(text: str) -> str:
    return next(
        line.split("=", 1)[1].strip()
        for line in text.splitlines()
        if line.startswith("ExecStart=")
    )


def test_console_entrypoint_metadata_points_at_module_main() -> None:
    document = tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))
    project = document["project"]
    assert project["name"] == "tirosh-vitalserver-redis-relay"
    assert project["requires-python"] == ">=3.12"
    assert project["dependencies"] == []
    assert project["scripts"] == {
        "vitalserver-redis-relay": "vitalserver_redis_relay.__main__:main"
    }
    wheel = document["tool"]["hatch"]["build"]["targets"]["wheel"]
    assert wheel["packages"] == ["vitalserver_redis_relay"]
    assert "vitalserver_redis_relay" in wheel["only-include"]


def test_dockerfile_keeps_python_module_entrypoint() -> None:
    text = DOCKERFILE.read_text(encoding="utf-8")
    assert 'CMD ["python", "-m", "vitalserver_redis_relay"]' in text
    assert "vitalserver-redis-relay" not in text.split("CMD", 1)[1]


def test_duplicate_draft_package_is_removed() -> None:
    assert not DUPLICATE_DRAFT.exists()


def test_example_native_configs_match_supervisor_paths() -> None:
    macos = tomllib.loads(MACOS_EXAMPLE_TOML.read_text(encoding="utf-8"))
    linux = tomllib.loads(LINUX_EXAMPLE_TOML.read_text(encoding="utf-8"))
    arguments = launchd_program_arguments(LAUNCHD_PLIST.read_text(encoding="utf-8"))
    exec_start = systemd_exec_start(SYSTEMD_UNIT.read_text(encoding="utf-8")).split()
    assert arguments[arguments.index("--config-path") + 1] == (
        "/usr/local/etc/vitalserver/redis-relay.toml"
    )
    assert exec_start[exec_start.index("--config-path") + 1] == (
        "/etc/vitalserver/redis-relay.toml"
    )
    for document, username, password in (
        (
            macos,
            "/usr/local/etc/vitalserver/secrets/redis-relay-target-username",
            "/usr/local/etc/vitalserver/secrets/redis-relay-target-password",
        ),
        (
            linux,
            "/etc/vitalserver/secrets/redis-relay-target-username",
            "/etc/vitalserver/secrets/redis-relay-target-password",
        ),
    ):
        source = document["source"]
        target = document["target"]
        assert source["host"] == "127.0.0.1"
        assert "password" not in source
        assert "username" not in target
        assert "password" not in target
        assert target["username_file"] == username
        assert target["password_file"] == password
        assert "@" not in target["url"]


def test_supervisor_executables_match_operations_and_unit_files() -> None:
    contract = supervisor_contract_from_operations()
    operations = OPERATIONS.read_text(encoding="utf-8")
    macos = contract["macOS"]
    linux = contract["Linux"]
    macos_exec = f"{macos['venv']}/bin/{CONSOLE_NAME}"
    linux_exec = f"{linux['venv']}/bin/{CONSOLE_NAME}"
    assert macos["executable"] == macos_exec
    assert linux["executable"] == linux_exec
    assert f"uv venv {macos['venv']}" in operations
    assert f"uv venv {linux['venv']}" in operations
    assert f"--python {macos['venv']}/bin/python" in operations
    assert f"--python {linux['venv']}/bin/python" in operations
    arguments = launchd_program_arguments(LAUNCHD_PLIST.read_text(encoding="utf-8"))
    exec_start = systemd_exec_start(SYSTEMD_UNIT.read_text(encoding="utf-8"))
    assert arguments[0] == macos_exec
    assert exec_start.split()[0] == linux_exec
    assert macos_exec in operations
    assert linux_exec in operations
    assert ".venv-redis-relay" in operations
    assert (
        macos_exec
        not in operations.split("### 2-2. Development venv", 1)[1].split(
            "### 2-3. System executable 계약", 1
        )[0]
    )


def test_operations_install_commands_set_config_and_supervisor_file_ownership() -> None:
    operations = OPERATIONS.read_text(encoding="utf-8")
    expected = (
        (
            "/usr/local/etc/vitalserver/redis-relay.toml",
            "root:_vitalserver-redis-relay",
            "0640",
        ),
        (
            "/Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist",
            "root:wheel",
            "0644",
        ),
        (
            "/etc/vitalserver/redis-relay.toml",
            "root:vitalserver-redis-relay",
            "0640",
        ),
        (
            "/etc/systemd/system/vitalserver-redis-relay.service",
            "root:root",
            "0644",
        ),
    )
    for path, owner, mode in expected:
        table_owner, table_mode = operations_path_row(path)
        assert table_owner == owner
        assert table_mode == mode
        assert f"sudo chown {owner} {path}" in operations
        assert f"sudo chmod {mode} {path}" in operations


def test_launchd_plist_is_foreground_example_without_secrets() -> None:
    text = LAUNCHD_PLIST.read_text(encoding="utf-8")
    arguments = launchd_program_arguments(text)
    assert arguments[0].endswith(f"/venv/bin/{CONSOLE_NAME}")
    assert "<key>RunAtLoad</key>" in text
    assert "<key>KeepAlive</key>" in text
    assert "/usr/local/var/log/vitalserver/redis-relay.out.log" in text
    assert "/usr/local/var/log/vitalserver/redis-relay.err.log" in text
    operations = OPERATIONS.read_text(encoding="utf-8")
    assert "/usr/local/var/log/vitalserver" in operations
    assert "password" not in text.lower()
    assert "username_file" not in text
    assert "EnvironmentVariables" not in text
    plutil = Path("/usr/bin/plutil")
    if plutil.exists():
        subprocess.run(
            [str(plutil), "-lint", str(LAUNCHD_PLIST)],
            check=True,
            capture_output=True,
            text=True,
        )


def test_systemd_unit_is_foreground_example_without_secrets() -> None:
    text = SYSTEMD_UNIT.read_text(encoding="utf-8")
    assert "EXAMPLE systemd unit" in text
    assert "Type=simple" in text
    assert "User=vitalserver-redis-relay" in text
    assert "Restart=on-failure" in text
    exec_start = systemd_exec_start(text)
    assert exec_start.startswith("/")
    assert exec_start.split()[0].endswith(f"/venv/bin/{CONSOLE_NAME}")
    assert "--config-path /etc/vitalserver/redis-relay.toml" in exec_start
    assert "--status-path /var/lib/vitalserver/redis-relay/status.json" in exec_start
    assert "password" not in text.lower()
    assert "Environment=" not in text
    assert "EnvironmentFile=" not in text


@pytest.fixture(scope="module")
def built_wheel(tmp_path_factory: pytest.TempPathFactory) -> Path:
    dist = tmp_path_factory.mktemp("relay-dist")
    result = subprocess.run(
        [
            "uv",
            "build",
            "--package",
            "tirosh-vitalserver-redis-relay",
            "--wheel",
            "--out-dir",
            str(dist),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"uv build failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    wheels = list(dist.glob("tirosh_vitalserver_redis_relay-*.whl"))
    assert wheels, f"wheel missing from {dist}: {result.stdout}\n{result.stderr}"
    return wheels[0]


@pytest.fixture(scope="module")
def installed_venv(
    built_wheel: Path, tmp_path_factory: pytest.TempPathFactory
) -> Iterator[Path]:
    root = tmp_path_factory.mktemp("relay-venv")
    venv = root / "venv"
    create = subprocess.run(
        ["uv", "venv", str(venv)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if create.returncode != 0:
        raise AssertionError(
            f"uv venv failed\nstdout:\n{create.stdout}\nstderr:\n{create.stderr}"
        )
    python = venv / "bin" / "python"
    install = subprocess.run(
        [
            "uv",
            "pip",
            "install",
            "--python",
            str(python),
            "--no-deps",
            str(built_wheel),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if install.returncode != 0:
        raise AssertionError(
            "uv pip install --no-deps failed\n"
            f"stdout:\n{install.stdout}\n"
            f"stderr:\n{install.stderr}"
        )
    yield venv


def test_wheel_contains_runtime_package_without_tests_or_draft(
    built_wheel: Path,
) -> None:
    with zipfile.ZipFile(built_wheel) as archive:
        names = archive.namelist()
    assert any(name.startswith("vitalserver_redis_relay/") for name in names)
    assert any(name.endswith("vitalserver_redis_relay/__main__.py") for name in names)
    joined = "\n".join(names)
    assert "tests/" not in joined
    assert "packaging/" not in joined
    assert "tirosh_vitalserver/redis_relay/" not in joined
    assert "packages/vitalserver-redis-relay" not in joined
    with zipfile.ZipFile(built_wheel) as archive:
        contents = "\n".join(
            archive.read(name).decode("utf-8", errors="replace")
            for name in names
            if name.endswith(".py")
        )
    assert "sentinel-password" not in contents
    assert "from redis import Redis" not in contents


def test_installed_console_and_module_help_use_the_same_command(
    installed_venv: Path,
) -> None:
    console = installed_venv / "bin" / "vitalserver-redis-relay"
    python = installed_venv / "bin" / "python"
    console_help = subprocess.run(
        [str(console), "--help"],
        capture_output=True,
        text=True,
        check=True,
    )
    module_help = subprocess.run(
        [str(python), "-m", "vitalserver_redis_relay", "--help"],
        capture_output=True,
        text=True,
        check=True,
    )
    assert "--config-path" in console_help.stdout
    assert "--status-path" in console_help.stdout
    assert "VitalServer Redis relay" in console_help.stdout
    assert "VitalServer Redis relay" in module_help.stdout
    _, console_body = console_help.stdout.split("VitalServer Redis relay", 1)
    _, module_body = module_help.stdout.split("VitalServer Redis relay", 1)
    assert console_body == module_body
    inspect = subprocess.run(
        [
            str(python),
            "-c",
            "import vitalserver_redis_relay, vitalserver_redis_relay.__main__ as m; "
            "print(m.main.__module__)",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    assert inspect.stdout.strip() == "vitalserver_redis_relay.__main__"


def test_installed_console_writes_disabled_status_then_stops_on_sigterm(
    installed_venv: Path,
    tmp_path: Path,
) -> None:
    config = tmp_path / "redis-relay.toml"
    status = tmp_path / "redis-relay-status.json"
    config.write_text(
        "[redis_relay]\nenabled = false\n",
        encoding="utf-8",
    )
    command = installed_venv / "bin" / "vitalserver-redis-relay"
    process = subprocess.Popen(
        [
            str(command),
            "--config-path",
            str(config),
            "--status-path",
            str(status),
        ],
        cwd=tmp_path,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        deadline = time.monotonic() + 10
        document: dict[str, object] | None = None
        while time.monotonic() < deadline:
            if status.is_file():
                loaded = json.loads(status.read_text(encoding="utf-8"))
                if (
                    loaded.get("schemaVersion") == 1
                    and loaded.get("state") == "disabled"
                ):
                    document = loaded
                    break
            time.sleep(0.05)
        assert document is not None, (
            "disabled status was not written\n"
            f"stdout:{process.stdout}\nstderr:{process.stderr}"
        )
        assert document["enabled"] is False
        assert "password" not in json.dumps(document)
        process.send_signal(signal.SIGTERM)
        process.wait(timeout=5)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
    assert process.returncode is not None
    assert not str(tmp_path).startswith("/Library")
    assert not str(tmp_path).startswith("/etc")
