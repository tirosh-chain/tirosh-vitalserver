from __future__ import annotations

import os
import shutil
import subprocess
from argparse import Namespace
from pathlib import Path

from tirosh_vitalserver.devtools.host_proxy.local_proxy import (
    run_proxy_test,
    run_proxy_write_config,
)
from tirosh_vitalserver.devtools.toolchain.workspace_paths import repo_root


def run_env_bootstrap(args: Namespace) -> int:
    root = repo_root()
    env_file = root / ".env"
    if env_file.is_file():
        print("ok: .env exists")
    else:
        shutil.copy2(root / ".env.example", env_file)
        print("created: .env from .env.example")
    run_proxy_write_config(args)
    if shutil.which(args.uv):
        print(f"Syncing Python workspace with {args.uv}")
        result = subprocess.run([args.uv, "sync"], cwd=root, check=False)
        if result.returncode == 0:
            print("ok: Python workspace synced")
        else:
            print(
                "warn: Python workspace sync failed; continuing because "
                "testkit/dev env is optional for make up"
            )
    else:
        print("uv not found; skipping Python workspace sync.")
        print("Install uv only when you need testkit, lint, typecheck, or pytest.")
    return run_env_doctor(args)


def run_env_doctor(args: Namespace) -> int:
    status = 0
    print("Checking local environment")
    for tool in ["git", args.python, "docker"]:
        status |= require_command(tool)
    status |= check_command(["docker", "info"], "Docker daemon")
    status |= check_command(["docker", "compose", "version"], "Docker Compose v2")
    status |= check_submodule()
    status |= check_nginx(args)
    status |= check_proxy_port(args)
    status |= check_compose(args)
    status |= check_uv_or_testkit(args)
    return status


def run_require_uv(args: Namespace) -> int:
    if shutil.which(args.uv):
        return 0
    raise SystemExit(
        "missing: uv\n"
        "Install uv to run Python testkit and developer checks.\n"
        "See https://docs.astral.sh/uv/getting-started/installation/"
    )


def require_command(tool: str) -> int:
    if shutil.which(tool):
        print(f"ok: {tool}")
        return 0
    print(f"missing: {tool}")
    return 1


def check_command(command: list[str], label: str) -> int:
    result = subprocess.run(
        command,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode == 0:
        print(f"ok: {label}")
        return 0
    print(f"missing: {label}")
    return 1


def check_submodule() -> int:
    if (repo_root() / "vendor/vitalserver/.git").exists():
        print("ok: vendor/vitalserver submodule")
        return 0
    print("missing: vendor/vitalserver submodule; run 'make init'")
    return 1


def check_nginx(args: Namespace) -> int:
    if Path(args.nginx_bin).is_file() or shutil.which(args.nginx_bin):
        print(f"ok: nginx ({args.nginx_bin})")
        return run_proxy_test(args)
    print(
        "missing: nginx; install with 'brew install nginx' "
        "or set NGINX_BIN=/path/to/nginx"
    )
    return 1


def check_proxy_port(args: Namespace) -> int:
    port = args.port
    if port.isdigit() and int(port) < 1024 and not shutil.which("sudo"):
        print(f"error: proxy port {port} requires root, but sudo is missing")
        return 1
    print(f"ok: proxy port {port} is configured")
    return 0


def check_compose(args: Namespace) -> int:
    env = {
        "VITALSERVER_BIND_HOST": args.bind_host,
        "VITALSERVER_HTTP_PORT": args.http_port,
        "VITALSERVER_TRUST_PROXY": args.trust_proxy,
    }
    command = [*args.compose.split(), "config"]
    result = subprocess.run(
        command,
        cwd=repo_root(),
        env={**os.environ, **env},
        check=False,
    )
    if result.returncode == 0:
        print(
            f"ok: compose config ({args.bind_host}:{args.http_port}, "
            f"trust_proxy={args.trust_proxy})"
        )
        return 0
    print("error: docker compose config is invalid")
    return 1


def check_uv_or_testkit(args: Namespace) -> int:
    if shutil.which(args.uv):
        print("ok: uv")
        return 0
    print("optional missing: uv; checking installed testkit package")
    result = subprocess.run(
        [
            args.python,
            "-c",
            "import pydantic_settings, tirosh_vitalserver.testkit",
        ],
        check=False,
    )
    if result.returncode == 0:
        print("ok: installed testkit runtime")
    else:
        print(
            "optional missing: installed testkit runtime; "
            "run 'make install-testkit-release'"
        )
    return 0
