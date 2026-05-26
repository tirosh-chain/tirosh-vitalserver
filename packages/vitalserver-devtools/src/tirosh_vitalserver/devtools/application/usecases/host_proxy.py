from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.host_proxy.local_proxy import (
    build_nginx_bundle,
    check_proxy_port,
    clean_proxy_runtime,
    inspect_proxy_status,
    reload_proxy,
    render_proxy_config,
    render_proxy_launchd_plist,
    start_proxy,
    stop_orphan_proxy_listeners,
    stop_proxy,
    test_proxy_config,
    write_proxy_config,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    HostProxyInput,
    NginxBundleInput,
)
from tirosh_vitalserver.devtools.config.host_proxy import load_nginx_bundle_config
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.config.release_manifest import load_release_manifest
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    host_proxy_expected_version,
)


def render_config(input: HostProxyInput) -> int:
    return render_proxy_config(input)


def write_config(input: HostProxyInput) -> int:
    return write_proxy_config(input)


def test_config(input: HostProxyInput) -> int:
    return test_proxy_config(input)


def start(input: HostProxyInput) -> int:
    return start_proxy(input)


def check_port(input: HostProxyInput) -> int:
    return check_proxy_port(input)


def stop(input: HostProxyInput) -> int:
    return stop_proxy(input)


def stop_orphans(input: HostProxyInput) -> int:
    return stop_orphan_proxy_listeners(input)


def clean(input: HostProxyInput) -> int:
    return clean_proxy_runtime(input)


def reload(input: HostProxyInput) -> int:
    return reload_proxy(input)


def status(input: HostProxyInput) -> int:
    return inspect_proxy_status(input)


def render_launchd_plist(input: HostProxyInput) -> int:
    return render_proxy_launchd_plist(input)


def build_nginx(input: NginxBundleInput) -> int:
    root = repo_root()
    config = load_config(input.config)
    expected_version = input.expected_version
    if expected_version is None and input.release_file:
        release_file = resolve_path(root, input.release_file)
        release = load_release_manifest(release_file)
        expected_version = host_proxy_expected_version(
            release=release,
            explicit_version=None,
        )
        input = NginxBundleInput(
            config=input.config,
            bundle_dir=input.bundle_dir,
            binary=input.binary,
            expected_version=expected_version,
            release_file=input.release_file,
        )
    return build_nginx_bundle(input, load_nginx_bundle_config(config, root))
