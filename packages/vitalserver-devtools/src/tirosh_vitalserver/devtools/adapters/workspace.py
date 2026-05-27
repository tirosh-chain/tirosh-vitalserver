from __future__ import annotations

import os
import subprocess
import webbrowser

from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root


def execute_compose(
    *,
    compose: str,
    compose_args: list[str],
    environment: dict[str, str],
) -> int:
    return subprocess.run(
        [*compose.split(), *compose_args],
        cwd=repo_root(),
        env={**os.environ, **environment},
        check=False,
    ).returncode


def configured_product_url() -> str | None:
    return os.environ.get("VITALSERVER_URL")


def open_url(url: str) -> None:
    webbrowser.open_new_tab(url)


def execute_python_tool(*, uv: str, tool_args: list[str]) -> int:
    return subprocess.run(
        [uv, "run", *tool_args],
        cwd=repo_root(),
        check=False,
    ).returncode
