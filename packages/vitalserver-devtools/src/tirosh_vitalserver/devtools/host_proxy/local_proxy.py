from __future__ import annotations

import os
import shutil
import subprocess
import urllib.request
from argparse import Namespace
from pathlib import Path

from tirosh_vitalserver.devtools.toolchain.workspace_paths import repo_root


def run_proxy_config(args: Namespace) -> int:
    print(render_proxy_config(args.port, args.upstream), end="")
    return 0


def run_proxy_write_config(args: Namespace) -> int:
    config = resolve_repo_path(args.config)
    (resolve_repo_path(args.runtime_dir) / "logs").mkdir(parents=True, exist_ok=True)
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(render_proxy_config(args.port, args.upstream), encoding="utf-8")
    print(f"Wrote {args.config}")
    return 0


def run_proxy_test(args: Namespace) -> int:
    write_proxy_config(args)
    return run_nginx(args, ["-t"])


def run_proxy_start(args: Namespace) -> int:
    write_proxy_config(args)
    test_status = run_nginx(args, ["-t"])
    if test_status != 0:
        return test_status
    pid = read_pid(args)
    if pid and process_is_running(pid):
        status = run_nginx(args, ["-s", "reload"])
        if status == 0:
            print(f"Proxy reloaded: http://localhost:{args.port} -> http://{args.upstream}")
        return status
    status = check_port_available(args)
    if status != 0:
        return status
    status = run_nginx(args, [])
    if status == 0:
        print(f"Proxy: http://localhost:{args.port} -> http://{args.upstream}")
    return status


def run_proxy_reload(args: Namespace) -> int:
    write_proxy_config(args)
    test_status = run_nginx(args, ["-t"])
    if test_status != 0:
        return test_status
    return run_nginx(args, ["-s", "reload"])


def run_proxy_port_check(args: Namespace) -> int:
    return check_port_available(args)


def run_proxy_stop(args: Namespace) -> int:
    pid = read_pid(args)
    if pid and process_is_running(pid):
        status = run_nginx(args, ["-s", "quit"])
        if status == 0:
            print(f"nginx proxy stop requested: pid {pid}")
        return status
    if resolve_repo_path(args.config).is_file():
        print("nginx proxy pid file is missing or stale; trying config-based stop")
        status = run_nginx(args, ["-s", "quit"], quiet=True)
        if status == 0:
            print("nginx proxy stop requested with config")
            return 0
    print("nginx proxy is already stopped")
    warn_remaining_listeners(args.port)
    return 0


def run_proxy_stop_orphans(args: Namespace) -> int:
    pids = nginx_listener_pids(args.port)
    if not pids:
        print(f"no nginx listeners on port {args.port}")
        return 0
    print(f"stopping orphan nginx listeners on port {args.port}: {' '.join(pids)}")
    command = [*kill_command(args.port), "-TERM", *pids]
    return subprocess.run(command, check=False).returncode


def run_proxy_clean(args: Namespace) -> int:
    stop_status = run_proxy_stop(args)
    orphan_status = run_proxy_stop_orphans(args)
    runtime_dir = resolve_repo_path(args.runtime_dir)
    if runtime_dir.exists():
        shutil.rmtree(runtime_dir)
    return stop_status or orphan_status


def run_proxy_status(args: Namespace) -> int:
    pid = read_pid(args)
    if pid and process_is_running(pid):
        print(f"nginx proxy is running: pid {pid}")
    elif pid:
        print(f"nginx proxy pid file exists, but process is not running: {pid}")
    else:
        print(f"nginx proxy is not running: missing {args.runtime_dir}/logs/nginx.pid")
    listeners = port_listeners(args.port)
    if listeners:
        print(f"proxy port {args.port} listeners: {','.join(listeners)}")
    else:
        print(f"proxy port {args.port} has no listener")
    backend_url = f"http://{args.bind_host}:{args.http_port}/check"
    if http_ok(backend_url):
        print(f"backend is reachable: {backend_url}")
    else:
        print(f"backend is not reachable: {backend_url}")
        print(
            "hint: run 'docker compose ps' and check that app publishes "
            f"{args.bind_host}:{args.http_port}"
        )
    return 0


def run_proxy_plist(args: Namespace) -> int:
    template = (
        repo_root() / "infra/macos-nginx/com.tirosh.vitalserver-proxy.plist.template"
    )
    rendered = (
        template.read_text(encoding="utf-8")
        .replace("${NGINX_BIN}", args.nginx_bin)
        .replace("${NGINX_CONF}", args.nginx_conf)
        .replace("${NGINX_PREFIX}", args.nginx_prefix)
    )
    print(rendered, end="")
    return 0


def write_proxy_config(args: Namespace) -> None:
    config = resolve_repo_path(args.config)
    (resolve_repo_path(args.runtime_dir) / "logs").mkdir(parents=True, exist_ok=True)
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(render_proxy_config(args.port, args.upstream), encoding="utf-8")
    print(f"Wrote {args.config}")


def render_proxy_config(port: str, upstream: str) -> str:
    template = repo_root() / "infra/macos-nginx/vitalserver.conf.template"
    return (
        template.read_text(encoding="utf-8")
        .replace("${VITALSERVER_PROXY_PORT}", port)
        .replace("${PROXY_UPSTREAM}", upstream)
    )


def run_nginx(
    args: Namespace,
    extra: list[str],
    *,
    quiet: bool = False,
) -> int:
    command = [
        *nginx_command(args.port, args.nginx_bin),
        "-p",
        str(resolve_repo_path(args.runtime_dir)),
        "-c",
        str(resolve_repo_path(args.config)),
        *extra,
    ]
    stdout = subprocess.DEVNULL if quiet else None
    stderr = subprocess.DEVNULL if quiet else None
    return subprocess.run(command, stdout=stdout, stderr=stderr, check=False).returncode


def nginx_command(port: str, nginx_bin: str) -> list[str]:
    if requires_sudo(port):
        return ["sudo", nginx_bin]
    return [nginx_bin]


def kill_command(port: str) -> list[str]:
    if requires_sudo(port):
        return ["sudo", "kill"]
    return ["kill"]


def requires_sudo(port: str) -> bool:
    return port.isdigit() and int(port) < 1024 and os.geteuid() != 0


def check_port_available(args: Namespace) -> int:
    pid = read_pid(args)
    listeners = port_listeners(args.port)
    if pid:
        listeners = [
            listener for listener in listeners if not listener.endswith(f"/{pid}")
        ]
    if listeners:
        print(
            f"error: proxy port {args.port} is already in use by {','.join(listeners)}",
            flush=True,
        )
        print("Stop that process or use VITALSERVER_PROXY_PORT=<port>.")
        return 1
    return 0


def read_pid(args: Namespace) -> str:
    pid_file = resolve_repo_path(args.runtime_dir) / "logs/nginx.pid"
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
    if not shutil.which("lsof"):
        return []
    result = subprocess.run(
        ["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN"],
        text=True,
        capture_output=True,
        check=False,
    )
    listeners = []
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2:
            listeners.append(f"{fields[0]}/{fields[1]}")
    return sorted(set(listeners))


def nginx_listener_pids(port: str) -> list[str]:
    if not shutil.which("lsof"):
        raise SystemExit("error: lsof is required to find orphan proxy listeners")
    result = subprocess.run(
        ["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN"],
        text=True,
        capture_output=True,
        check=False,
    )
    pids = []
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2 and fields[0] == "nginx":
            pids.append(fields[1])
    return sorted(set(pids))


def warn_remaining_listeners(port: str) -> None:
    listeners = port_listeners(port)
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
