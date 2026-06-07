from __future__ import annotations

import os
import shutil
import subprocess
import urllib.request
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.host_proxy.nginx_bundle import (
    run_nginx_bundle,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    HostProxyInput,
    NginxBundleInput,
)
from tirosh_vitalserver.devtools.core.host_proxy import (
    NginxBundleConfig,
    listeners_excluding_proxy_pid,
    proxy_config_text,
    proxy_launchd_plist_text,
)
from tirosh_vitalserver.devtools.core.host_proxy import (
    kill_command as proxy_kill_command,
)
from tirosh_vitalserver.devtools.core.host_proxy import (
    nginx_command as proxy_nginx_command,
)
from tirosh_vitalserver.devtools.core.host_proxy import (
    requires_sudo as proxy_requires_sudo,
)


class PortListenerScanError(RuntimeError):
    pass


def render_proxy_config(input: HostProxyInput) -> int:
    print(render_proxy_config_text(input.port, input.upstream), end="")
    return 0


def write_proxy_config(input: HostProxyInput) -> int:
    config = resolve_repo_path(input.proxy_config)
    ensure_nginx_runtime_dirs(resolve_repo_path(input.runtime_dir))
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(
        render_proxy_config_text(input.port, input.upstream),
        encoding="utf-8",
    )
    print(f"Wrote {input.proxy_config}")
    return 0


def test_proxy_config(input: HostProxyInput) -> int:
    write_proxy_config_file(input)
    return run_nginx(input, ["-t"])


def start_proxy(input: HostProxyInput) -> int:
    write_proxy_config_file(input)
    test_status = run_nginx(input, ["-t"])
    if test_status != 0:
        return test_status
    pid = read_pid(input)
    if pid and process_is_running(pid):
        status = run_nginx(input, ["-s", "reload"])
        if status == 0:
            print(
                "Proxy reloaded: "
                f"http://localhost:{input.port} -> http://{input.upstream}"
            )
        return status
    status = check_port_available(input)
    if status != 0:
        return status
    status = run_nginx(input, [])
    if status == 0:
        print(f"Proxy: http://localhost:{input.port} -> http://{input.upstream}")
    return status


def reload_proxy(input: HostProxyInput) -> int:
    write_proxy_config_file(input)
    test_status = run_nginx(input, ["-t"])
    if test_status != 0:
        return test_status
    return run_nginx(input, ["-s", "reload"])


def check_proxy_port(input: HostProxyInput) -> int:
    return check_port_available(input)


def stop_proxy(input: HostProxyInput) -> int:
    pid = read_pid(input)
    if pid and process_is_running(pid):
        status = run_nginx(input, ["-s", "quit"])
        if status == 0:
            print(f"nginx proxy stop requested: pid {pid}")
        return status
    if resolve_repo_path(input.proxy_config).is_file():
        print("nginx proxy pid file is missing or stale; trying config-based stop")
        status = run_nginx(input, ["-s", "quit"], quiet=True)
        if status == 0:
            print("nginx proxy stop requested with config")
            return 0
    print("nginx proxy is already stopped")
    warn_remaining_listeners(input.port)
    return 0


def stop_orphan_proxy_listeners(input: HostProxyInput) -> int:
    pids = nginx_listener_pids(input.port)
    if not pids:
        print(f"no nginx listeners on port {input.port}")
        return 0
    print(f"stopping orphan nginx listeners on port {input.port}: {' '.join(pids)}")
    command = [*kill_command(input.port), "-TERM", *pids]
    return subprocess.run(command, check=False).returncode


def clean_proxy_runtime(input: HostProxyInput) -> int:
    stop_status = stop_proxy(input)
    orphan_status = stop_orphan_proxy_listeners(input)
    runtime_dir = resolve_repo_path(input.runtime_dir)
    if runtime_dir.exists():
        shutil.rmtree(runtime_dir)
    return stop_status or orphan_status


def inspect_proxy_status(input: HostProxyInput) -> int:
    status = 0
    pid = read_pid(input)
    if pid and process_is_running(pid):
        print(f"nginx proxy is running: pid {pid}")
    elif pid:
        print(f"nginx proxy pid file exists, but process is not running: {pid}")
    else:
        print(f"nginx proxy is not running: missing {input.runtime_dir}/logs/nginx.pid")
    try:
        listeners = port_listeners(input.port)
        if listeners:
            print(f"proxy port {input.port} listeners: {','.join(listeners)}")
        else:
            print(f"proxy port {input.port} has no listener")
    except PortListenerScanError as error:
        print(f"error: {error}")
        status = 1
    backend_url = f"http://{input.bind_host}:{input.http_port}/check"
    if http_ok(backend_url):
        print(f"backend is reachable: {backend_url}")
    else:
        print(f"backend is not reachable: {backend_url}")
        print(
            "hint: run 'docker compose ps' and check that app publishes "
            f"{input.bind_host}:{input.http_port}"
        )
    return status


def render_proxy_launchd_plist(input: HostProxyInput) -> int:
    template = (
        repo_root() / "infra/macos-nginx/com.tirosh.vitalserver-proxy.plist.template"
    )
    rendered = proxy_launchd_plist_text(
        template=template.read_text(encoding="utf-8"),
        nginx_bin=input.nginx_bin,
        nginx_conf=input.nginx_conf,
        nginx_prefix=input.nginx_prefix,
    )
    print(rendered, end="")
    return 0


def build_nginx_bundle(input: NginxBundleInput, config: NginxBundleConfig) -> int:
    return run_nginx_bundle(input, config)


def write_proxy_config_file(input: HostProxyInput) -> None:
    config = resolve_repo_path(input.proxy_config)
    ensure_nginx_runtime_dirs(resolve_repo_path(input.runtime_dir))
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(
        render_proxy_config_text(input.port, input.upstream),
        encoding="utf-8",
    )
    print(f"Wrote {input.proxy_config}")


def ensure_nginx_runtime_dirs(runtime_dir: Path) -> None:
    for relative_path in [
        "logs",
        "temp/client_body",
        "temp/proxy",
        "temp/fastcgi",
        "temp/uwsgi",
        "temp/scgi",
    ]:
        (runtime_dir / relative_path).mkdir(parents=True, exist_ok=True)


def render_proxy_config_text(port: str, upstream: str) -> str:
    template = repo_root() / "infra/macos-nginx/vitalserver.conf.template"
    return proxy_config_text(port, upstream, template.read_text(encoding="utf-8"))


def run_nginx(
    input: HostProxyInput,
    extra: list[str],
    *,
    quiet: bool = False,
) -> int:
    command = [
        *nginx_command(input.port, input.nginx_bin),
        "-p",
        str(resolve_repo_path(input.runtime_dir)),
        "-c",
        str(resolve_repo_path(input.proxy_config)),
        *extra,
    ]
    stdout = subprocess.DEVNULL if quiet else None
    stderr = subprocess.DEVNULL if quiet else None
    return subprocess.run(command, stdout=stdout, stderr=stderr, check=False).returncode


def nginx_command(port: str, nginx_bin: str) -> list[str]:
    return proxy_nginx_command(port, nginx_bin, os.geteuid())


def kill_command(port: str) -> list[str]:
    return proxy_kill_command(port, os.geteuid())


def requires_sudo(port: str) -> bool:
    return proxy_requires_sudo(port, os.geteuid())


def check_port_available(input: HostProxyInput) -> int:
    pid = read_pid(input)
    try:
        listeners = port_listeners(input.port)
    except PortListenerScanError as error:
        print(f"error: {error}", flush=True)
        return 1
    listeners = listeners_excluding_proxy_pid(
        listeners,
        pid=pid,
        pid_is_running=process_is_running(pid),
    )
    if listeners:
        print(
            f"error: proxy port {input.port} is already in use by "
            f"{','.join(listeners)}",
            flush=True,
        )
        print("Stop that process or use VITALSERVER_PROXY_PORT=<port>.")
        return 1
    return 0


def read_pid(input: HostProxyInput) -> str:
    pid_file = resolve_repo_path(input.runtime_dir) / "logs/nginx.pid"
    if pid_file.is_file():
        return pid_file.read_text(encoding="utf-8").strip()
    return ""


def process_is_running(pid: str) -> bool:
    try:
        os.kill(int(pid), 0)
    except (OSError, ValueError):
        return False
    return True


def port_listeners(port: str) -> list[str]:
    return sorted({f"{command}/{pid}" for command, pid in lsof_listener_rows(port)})


def lsof_listener_rows(port: str) -> list[tuple[str, str]]:
    lsof_path = shutil.which("lsof")
    if not lsof_path:
        raise PortListenerScanError("lsof is required to inspect proxy port listeners")
    try:
        result = subprocess.run(
            [lsof_path, "-nP", f"-iTCP:{port}", "-sTCP:LISTEN"],
            text=True,
            capture_output=True,
            check=False,
        )
    except (OSError, UnicodeDecodeError) as error:
        raise PortListenerScanError(
            f"failed to inspect proxy port {port} listeners: {error}"
        ) from error
    if result.returncode != 0:
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        if result.returncode == 1 and not stdout and not stderr:
            return []
        detail = stderr or stdout or f"exitCode={result.returncode}"
        raise PortListenerScanError(
            f"failed to inspect proxy port {port} listeners: {detail}"
        )
    listeners = []
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) < 2:
            raise PortListenerScanError(
                f"failed to inspect proxy port {port} listeners: malformed lsof output"
            )
        listeners.append((fields[0], fields[1]))
    return listeners


def nginx_listener_pids(port: str) -> list[str]:
    try:
        rows = lsof_listener_rows(port)
    except PortListenerScanError as error:
        raise SystemExit(f"error: {error}") from error
    return sorted({pid for command, pid in rows if command == "nginx"})


def warn_remaining_listeners(port: str) -> None:
    try:
        listeners = port_listeners(port)
    except PortListenerScanError as error:
        print(f"warning: could not inspect remaining listeners on port {port}: {error}")
        return
    if listeners:
        print(f"warning: listeners remain on port {port}: {','.join(listeners)}")
        print(f"Run: make proxy-stop-orphans VITALSERVER_PROXY_PORT={port}")


def http_ok(url: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=2):
            return True
    except Exception:
        return False


def resolve_repo_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else repo_root() / path
