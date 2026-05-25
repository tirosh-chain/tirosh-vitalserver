from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.environment import (
    command_exists,
    create_env_file_from_example,
    installed_testkit_runtime,
    run_command_quiet,
    run_compose_config,
    submodule_exists,
    sync_python_workspace,
)
from tirosh_vitalserver.devtools.adapters.host_proxy.local_proxy import (
    check_proxy_port as run_check_proxy_port,
)
from tirosh_vitalserver.devtools.adapters.host_proxy.local_proxy import (
    test_proxy_config,
    write_proxy_config,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    EnvironmentInput,
    HostProxyInput,
)


def bootstrap_environment(input: EnvironmentInput) -> int:
    root = repo_root()
    if create_env_file_from_example(root):
        print("created: .env from .env.example")
    else:
        print("ok: .env exists")
    write_proxy_config(input.proxy)
    if command_exists(input.uv):
        print(f"Syncing Python workspace with {input.uv}")
        status = sync_python_workspace(root, input.uv)
        if status == 0:
            print("ok: Python workspace synced")
        else:
            print(
                "warn: Python workspace sync failed; continuing because "
                "testkit/dev env is optional for make up"
            )
    else:
        print("uv not found; skipping Python workspace sync.")
        print("Install uv only when you need testkit, lint, typecheck, or pytest.")
    return diagnose_environment(input)


def diagnose_environment(input: EnvironmentInput) -> int:
    status = 0
    print("Checking local environment")
    for tool in ["git", input.python, "docker"]:
        status |= require_command(tool)
    status |= check_command(["docker", "info"], "Docker daemon")
    status |= check_command(
        ["docker", "compose", "version"],
        "Docker Compose v2",
    )
    status |= check_submodule()
    status |= check_nginx(input)
    status |= check_proxy_port(input.proxy)
    status |= check_compose(input)
    status |= check_uv_or_testkit(input)
    return status


def require_uv(input: EnvironmentInput) -> int:
    if command_exists(input.uv):
        return 0
    raise SystemExit(
        "missing: uv\n"
        "Install uv to run Python testkit and developer checks.\n"
        "See https://docs.astral.sh/uv/getting-started/installation/"
    )


def require_command(tool: str) -> int:
    if command_exists(tool):
        print(f"ok: {tool}")
        return 0
    print(f"missing: {tool}")
    return 1


def check_command(
    command: list[str],
    label: str,
) -> int:
    if run_command_quiet(command):
        print(f"ok: {label}")
        return 0
    print(f"missing: {label}")
    return 1


def check_submodule() -> int:
    if submodule_exists(repo_root()):
        print("ok: vendor/vitalserver submodule")
        return 0
    print("missing: vendor/vitalserver submodule; run 'make init'")
    return 1


def check_nginx(input: EnvironmentInput) -> int:
    if command_exists(input.proxy.nginx_bin):
        print(f"ok: nginx ({input.proxy.nginx_bin})")
        return test_proxy_config(input.proxy)
    print(
        "missing: nginx; install with 'brew install nginx' "
        "or set NGINX_BIN=/path/to/nginx"
    )
    return 1


def check_proxy_port(input: HostProxyInput) -> int:
    status = run_check_proxy_port(input)
    if status == 0:
        print(f"ok: proxy port {input.port} is available")
    return status


def check_compose(input: EnvironmentInput) -> int:
    if run_compose_config(input.proxy, input.compose):
        print(
            f"ok: compose config ({input.proxy.bind_host}:{input.proxy.http_port}, "
            f"trust_proxy={input.proxy.trust_proxy})"
        )
        return 0
    print("error: docker compose config is invalid")
    return 1


def check_uv_or_testkit(input: EnvironmentInput) -> int:
    if command_exists(input.uv):
        print("ok: uv")
        return 0
    print("optional missing: uv; checking installed testkit package")
    if installed_testkit_runtime(input.python):
        print("ok: installed testkit runtime")
    else:
        print(
            "optional missing: installed testkit runtime; "
            "run 'make install-testkit-release'"
        )
    return 0
