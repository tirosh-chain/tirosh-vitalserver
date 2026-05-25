from __future__ import annotations

import os
import subprocess
import webbrowser
from argparse import Namespace

from tirosh_vitalserver.devtools.toolchain.workspace_paths import repo_root


def run_compose(args: Namespace) -> int:
    command = [*args.compose.split(), *without_separator(args.compose_args)]
    return subprocess.run(
        command,
        cwd=repo_root(),
        env={**os.environ, **compose_env(args)},
        check=False,
    ).returncode


def run_open(args: Namespace) -> int:
    url = os.environ.get("VITALSERVER_URL")
    if not url:
        url = "http://localhost" if args.port == "80" else f"http://localhost:{args.port}"
    print(f"VitalServer: {url}")
    webbrowser.open_new_tab(url)
    return 0


def run_python_tool(args: Namespace) -> int:
    command = [args.uv, "run", *without_separator(args.tool_args)]
    return subprocess.run(command, cwd=repo_root(), check=False).returncode


def compose_env(args: Namespace) -> dict[str, str]:
    return {
        "VITALSERVER_BIND_HOST": args.bind_host,
        "VITALSERVER_HTTP_PORT": args.http_port,
        "VITALSERVER_REDIS_HOST": args.redis_host,
        "VITALSERVER_REDIS_PORT": args.redis_port,
        "VITALSERVER_TRUST_PROXY": args.trust_proxy,
    }


def without_separator(args: list[str]) -> list[str]:
    if args and args[0] == "--":
        return args[1:]
    return args
