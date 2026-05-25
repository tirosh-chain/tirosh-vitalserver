from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape


@dataclass(frozen=True)
class NginxBundleConfig:
    binary_path: Path
    expected_version: str
    non_system_dylib_prefixes: tuple[str, ...]


def proxy_config_text(port: str, upstream: str, template: str) -> str:
    return (
        template.replace("${VITALSERVER_PROXY_PORT}", port).replace(
            "${PROXY_UPSTREAM}",
            upstream,
        )
    )


def proxy_launchd_plist_text(
    *,
    template: str,
    nginx_bin: str,
    nginx_conf: str,
    nginx_prefix: str,
) -> str:
    return (
        template.replace("${NGINX_BIN}", plist_text(nginx_bin))
        .replace("${NGINX_CONF}", plist_text(nginx_conf))
        .replace("${NGINX_PREFIX}", plist_text(nginx_prefix))
    )


def plist_text(value: str) -> str:
    return xml_escape(value)


def requires_sudo(port: str, effective_uid: int) -> bool:
    return port.isdigit() and int(port) < 1024 and effective_uid != 0


def nginx_command(port: str, nginx_bin: str, effective_uid: int) -> list[str]:
    if requires_sudo(port, effective_uid):
        return ["sudo", nginx_bin]
    return [nginx_bin]


def kill_command(port: str, effective_uid: int) -> list[str]:
    if requires_sudo(port, effective_uid):
        return ["sudo", "kill"]
    return ["kill"]


def listeners_excluding_proxy_pid(
    listeners: list[str],
    *,
    pid: str,
    pid_is_running: bool,
) -> list[str]:
    if not pid or not pid_is_running:
        return listeners
    return [listener for listener in listeners if not listener.endswith(f"/{pid}")]
