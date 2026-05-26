from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    TomlTable,
    nested_section,
    required_string,
    required_string_list,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.core.host_proxy import NginxBundleConfig


def load_nginx_bundle_config(config: TomlTable, root: Path) -> NginxBundleConfig:
    path = "macos.host_proxy.nginx"
    nginx = nested_section(config, path)
    source_binary_path = nginx.get("source_binary_path")
    if source_binary_path is not None and (
        not isinstance(source_binary_path, str) or not source_binary_path
    ):
        raise SystemExit(
            f"error: invalid string config value: {path}.source_binary_path"
        )
    expected_version = nginx.get("expected_version")
    if expected_version is not None and (
        not isinstance(expected_version, str) or not expected_version
    ):
        raise SystemExit(f"error: invalid string config value: {path}.expected_version")
    return NginxBundleConfig(
        binary_path=resolve_path(
            root,
            required_string(nginx, "binary_path", path=path),
        ),
        source_binary_path=(
            resolve_path(root, source_binary_path) if source_binary_path else None
        ),
        expected_version=expected_version,
        non_system_dylib_prefixes=tuple(
            required_string_list(nginx, "non_system_dylib_prefixes", path=path)
        ),
    )
