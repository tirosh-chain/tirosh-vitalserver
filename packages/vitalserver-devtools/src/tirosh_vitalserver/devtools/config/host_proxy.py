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
    return NginxBundleConfig(
        binary_path=resolve_path(
            root,
            required_string(nginx, "binary_path", path=path),
        ),
        expected_version=required_string(nginx, "expected_version", path=path),
        non_system_dylib_prefixes=tuple(
            required_string_list(nginx, "non_system_dylib_prefixes", path=path)
        ),
    )
