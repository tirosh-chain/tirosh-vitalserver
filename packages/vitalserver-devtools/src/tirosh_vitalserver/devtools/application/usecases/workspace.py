from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.workspace import (
    configured_product_url,
    execute_compose,
    execute_python_tool,
    open_url,
)
from tirosh_vitalserver.devtools.application.inputs import (
    ComposeCommandInput,
    OpenProductUrlInput,
    PythonWorkspaceToolInput,
)


def execute_compose_command(
    input: ComposeCommandInput,
) -> int:
    return execute_compose(
        compose=input.compose,
        compose_args=without_separator(input.compose_args),
        environment=compose_env(input),
    )


def open_product_url(input: OpenProductUrlInput) -> int:
    url = configured_product_url()
    if not url:
        url = (
            "http://localhost"
            if input.port == "80"
            else f"http://localhost:{input.port}"
        )
    print(f"VitalServer: {url}")
    open_url(url)
    return 0


def execute_python_workspace_tool(
    input: PythonWorkspaceToolInput,
) -> int:
    return execute_python_tool(
        uv=input.uv,
        tool_args=without_separator(input.tool_args),
    )


def compose_env(input: ComposeCommandInput) -> dict[str, str]:
    return {
        "VITALSERVER_BIND_HOST": input.bind_host,
        "VITALSERVER_HTTP_PORT": input.http_port,
        "VITALSERVER_REDIS_HOST": input.redis_host,
        "VITALSERVER_REDIS_PORT": input.redis_port,
        "VITALSERVER_TRUST_PROXY": input.trust_proxy,
    }


def without_separator(args: list[str]) -> list[str]:
    if args and args[0] == "--":
        return args[1:]
    return args
