from __future__ import annotations

import subprocess
import tomllib
import zipfile
from collections.abc import Iterator
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
PYPROJECT = APP_DIR / "pyproject.toml"
ROOT_PYPROJECT = REPO_ROOT / "pyproject.toml"
LOCKFILE = REPO_ROOT / "uv.lock"
DOCKERFILE = APP_DIR / "Dockerfile"
LAUNCHD_PLIST = APP_DIR / "packaging/macos/ai.tirosh.vitaldb-observer.plist"
CONSOLE_NAME = "vitaldb-observer"
PACKAGE_NAME = "tirosh-vitaldb-observer"
RUNTIME_PACKAGE = "vitaldb_observer"
MACOS_EXEC = f"/usr/local/libexec/{CONSOLE_NAME}/venv/bin/{CONSOLE_NAME}"


def launchd_program_arguments(text: str) -> list[str]:
    start = text.index("<key>ProgramArguments</key>")
    block = text[start:]
    block = block[block.index("<array>") : block.index("</array>")]
    return [
        line.split("<string>", 1)[1].split("</string>", 1)[0]
        for line in block.splitlines()
        if "<string>" in line
    ]


def test_console_entrypoint_metadata_points_at_server_main() -> None:
    document = tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))
    project = document["project"]
    assert project["name"] == PACKAGE_NAME
    assert project["version"] == "0.2.0"
    assert project["requires-python"] == ">=3.12"
    assert project["dependencies"] == []
    assert project["scripts"] == {CONSOLE_NAME: f"{RUNTIME_PACKAGE}.server:main"}
    wheel = document["tool"]["hatch"]["build"]["targets"]["wheel"]
    assert wheel["packages"] == [RUNTIME_PACKAGE]
    assert RUNTIME_PACKAGE in wheel["only-include"]


def test_root_workspace_lists_observer_without_root_dependency() -> None:
    document = tomllib.loads(ROOT_PYPROJECT.read_text(encoding="utf-8"))
    assert "apps/vitaldb-observer" in document["tool"]["uv"]["workspace"]["members"]
    assert PACKAGE_NAME not in document["project"]["dependencies"]
    lock = tomllib.loads(LOCKFILE.read_text(encoding="utf-8"))
    names = [package["name"] for package in lock["package"]]
    assert PACKAGE_NAME in names
    observer = next(
        package for package in lock["package"] if package["name"] == PACKAGE_NAME
    )
    assert observer["source"] == {"editable": "apps/vitaldb-observer"}
    assert PACKAGE_NAME in lock["manifest"]["members"]


def test_dockerfile_keeps_python_module_entrypoint() -> None:
    text = DOCKERFILE.read_text(encoding="utf-8")
    assert 'CMD ["python", "-m", "vitaldb_observer.server"]' in text
    assert CONSOLE_NAME not in text.split("CMD", 1)[1]


def test_runtime_sources_have_no_daemonize_or_pidfile() -> None:
    for path in (APP_DIR / RUNTIME_PACKAGE).rglob("*.py"):
        text = path.read_text(encoding="utf-8")
        assert "daemonize" not in text
        assert "pidfile" not in text.lower()
        assert "os.fork" not in text


def test_launchd_plist_is_foreground_example_without_secrets() -> None:
    text = LAUNCHD_PLIST.read_text(encoding="utf-8")
    arguments = launchd_program_arguments(text)
    assert arguments[0] == MACOS_EXEC
    assert arguments == [
        MACOS_EXEC,
        "--host",
        "127.0.0.1",
        "--port",
        "18084",
        "--redis-host",
        "127.0.0.1",
        "--redis-port",
        "6379",
        "--redis-database",
        "0",
        "--redis-password-file",
        "/usr/local/etc/vitaldb-observer/secrets/redis-password",
        "--access-log-path",
        (
            "/Library/Application Support/VitalServerHelper"
            "/logs/runtime/proxy-nginx.access.log"
        ),
    ]
    assert "<key>Label</key>" in text
    assert "ai.tirosh.vitaldb-observer" in text
    assert "<string>_vitaldb-observer</string>" in text
    assert "<key>RunAtLoad</key>" in text
    assert "<key>KeepAlive</key>" in text
    assert "/usr/local/var/log/vitalserver/vitaldb-observer.out.log" in text
    assert "/usr/local/var/log/vitalserver/vitaldb-observer.err.log" in text
    assert "<key>EnvironmentVariables</key>" not in text
    assert "0.0.0.0" not in text
    assert "daemonize" not in text.lower()
    assert "pidfile" not in text.lower()
    assert "--redis-password" not in arguments
    assert not any("@" in argument for argument in arguments)
    plutil = Path("/usr/bin/plutil")
    if plutil.exists():
        subprocess.run(
            [str(plutil), "-lint", str(LAUNCHD_PLIST)],
            check=True,
            capture_output=True,
            text=True,
        )


@pytest.fixture(scope="module")
def built_wheel(tmp_path_factory: pytest.TempPathFactory) -> Path:
    dist = tmp_path_factory.mktemp("observer-dist")
    result = subprocess.run(
        [
            "uv",
            "build",
            "--package",
            PACKAGE_NAME,
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
    wheels = list(dist.glob("tirosh_vitaldb_observer-*.whl"))
    assert wheels, f"wheel missing from {dist}: {result.stdout}\n{result.stderr}"
    return wheels[0]


@pytest.fixture(scope="module")
def installed_venv(
    built_wheel: Path, tmp_path_factory: pytest.TempPathFactory
) -> Iterator[Path]:
    root = tmp_path_factory.mktemp("observer-venv")
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


def test_wheel_contains_runtime_package_without_tests_or_packaging(
    built_wheel: Path,
) -> None:
    with zipfile.ZipFile(built_wheel) as archive:
        names = archive.namelist()
    assert any(name.startswith(f"{RUNTIME_PACKAGE}/") for name in names)
    assert any(name.endswith(f"{RUNTIME_PACKAGE}/server.py") for name in names)
    joined = "\n".join(names)
    assert "tests/" not in joined
    assert "packaging/" not in joined
    assert "secrets/" not in joined
    with zipfile.ZipFile(built_wheel) as archive:
        contents = "\n".join(
            archive.read(name).decode("utf-8", errors="replace")
            for name in names
            if name.endswith(".py")
        )
    assert "from redis import Redis" not in contents
    assert "import redis\n" not in contents
    assert "import redis " not in contents


def test_installed_console_and_module_help_use_the_same_command(
    installed_venv: Path,
) -> None:
    console = installed_venv / "bin" / CONSOLE_NAME
    python = installed_venv / "bin" / "python"
    console_help = subprocess.run(
        [str(console), "--help"],
        capture_output=True,
        text=True,
        check=True,
    )
    module_help = subprocess.run(
        [str(python), "-m", "vitaldb_observer.server", "--help"],
        capture_output=True,
        text=True,
        check=True,
    )
    for flag in (
        "--host",
        "--port",
        "--redis-host",
        "--redis-port",
        "--redis-database",
        "--redis-password-file",
        "--access-log-path",
    ):
        assert flag in console_help.stdout
        assert flag in module_help.stdout
    assert "VitalDB observer" in console_help.stdout
    assert "VitalDB observer" in module_help.stdout
    _, console_body = console_help.stdout.split("VitalDB observer", 1)
    _, module_body = module_help.stdout.split("VitalDB observer", 1)
    assert console_body == module_body
    assert "--redis-password " not in console_help.stdout
    inspect = subprocess.run(
        [
            str(python),
            "-c",
            "import vitaldb_observer.server as server; print(server.main.__module__)",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    assert inspect.stdout.strip() == "vitaldb_observer.server"


def test_canonical_docs_match_executable_and_plist_paths() -> None:
    readme = (APP_DIR / "README.md").read_text(encoding="utf-8")
    canonical = (REPO_ROOT / "docs/vitaldb-observer/index.md").read_text(
        encoding="utf-8"
    )
    secret = "/usr/local/etc/vitaldb-observer/secrets/redis-password"
    out_log = "/usr/local/var/log/vitalserver/vitaldb-observer.out.log"
    err_log = "/usr/local/var/log/vitalserver/vitaldb-observer.err.log"
    assert "../../docs/vitaldb-observer/index.md" in readme
    assert "docs/openapi/" not in readme
    assert "docs/openapi/" not in canonical
    assert "../api/vitaldb-observer.openapi.yaml" in canonical
    assert MACOS_EXEC in canonical
    assert "ai.tirosh.vitaldb-observer" in canonical
    assert secret in canonical
    assert CONSOLE_NAME in canonical
    assert "python -m vitaldb_observer.server" in canonical
    assert "--redis-password " not in canonical
    assert "echo password" not in canonical.lower()
    assert "<<EOF" not in canonical
    assert "_vitaldb-observer:_vitaldb-observer" not in canonical
    assert "`_vitaldb-observer:wheel`" in canonical
    assert "`0700`" in canonical
    assert "sudo install -d -o _vitaldb-observer -g wheel -m 0700" in canonical
    assert f"sudo touch {secret}" in canonical
    assert "sudo chown _vitaldb-observer:wheel" in canonical
    assert f"sudo chmod 0600 {secret}" in canonical
    assert f"sudo touch {out_log}" in canonical
    assert f"sudo chmod 0640 {out_log}" in canonical
    assert f"sudo touch {err_log}" in canonical
    assert f"sudo chmod 0640 {err_log}" in canonical
    assert "/dev/null" not in canonical
    readable = canonical.index(f"test -r \\\n  {secret}")
    nonempty = canonical.index(f"test -s \\\n  {secret}")
    bootstrap = canonical.index("launchctl bootstrap system")
    assert readable < nonempty < bootstrap
