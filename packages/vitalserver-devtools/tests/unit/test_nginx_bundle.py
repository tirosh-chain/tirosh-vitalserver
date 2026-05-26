from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.adapters.host_proxy.nginx_bundle import (
    resolve_bundle_binary,
)
from tirosh_vitalserver.devtools.core.host_proxy import NginxBundleConfig


def test_resolve_bundle_binary_refreshes_stale_cache(tmp_path: Path) -> None:
    cache = tmp_path / "cache/nginx"
    source = tmp_path / "source/nginx"
    write_fake_nginx(cache, "nginx/1.31.0")
    write_fake_nginx(source, "nginx/1.31.1")

    resolved = resolve_bundle_binary(
        input_binary=None,
        config=NginxBundleConfig(
            binary_path=cache,
            source_binary_path=source,
            expected_version=None,
            non_system_dylib_prefixes=(),
        ),
        expected_version="nginx/1.31.1",
    )

    assert resolved == cache.resolve()
    assert cache.read_text(encoding="utf-8") == source.read_text(encoding="utf-8")


def write_fake_nginx(path: Path, version: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!/bin/sh\nprintf '%s\\n' 'nginx version: {version}' >&2\n")
    path.chmod(0o755)
