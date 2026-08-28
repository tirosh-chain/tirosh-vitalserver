from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.host_proxy.nginx_bundle import (
    resolve_bundle_binary,
    resolve_dylib_source,
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


def test_resolve_dylib_source_accepts_bundled_sibling_library(
    tmp_path: Path,
) -> None:
    binary = tmp_path / "nginx/sbin/nginx"
    source = tmp_path / "nginx/lib/libpcre2-8.0.dylib"
    binary.parent.mkdir(parents=True)
    source.parent.mkdir(parents=True)
    binary.write_bytes(b"nginx")
    source.write_bytes(b"pcre2")

    resolved = resolve_dylib_source(
        binary=binary,
        load_path="@executable_path/../lib/libpcre2-8.0.dylib",
        prefixes=("/opt/homebrew/",),
    )

    assert resolved == source.resolve()


def test_resolve_dylib_source_rejects_missing_bundled_library(
    tmp_path: Path,
) -> None:
    binary = tmp_path / "nginx/sbin/nginx"
    binary.parent.mkdir(parents=True)
    binary.write_bytes(b"nginx")

    with pytest.raises(SystemExit, match="nginx bundled dylib is missing"):
        resolve_dylib_source(
            binary=binary,
            load_path="@executable_path/../lib/libpcre2-8.0.dylib",
            prefixes=("/opt/homebrew/",),
        )


def test_resolve_dylib_source_rejects_path_outside_sibling_library_directory(
    tmp_path: Path,
) -> None:
    binary = tmp_path / "nginx/sbin/nginx"
    binary.parent.mkdir(parents=True)
    binary.write_bytes(b"nginx")

    with pytest.raises(
        SystemExit,
        match="nginx bundled dylib escapes sibling lib directory",
    ):
        resolve_dylib_source(
            binary=binary,
            load_path="@executable_path/../../outside.dylib",
            prefixes=("/opt/homebrew/",),
        )


def write_fake_nginx(path: Path, version: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!/bin/sh\nprintf '%s\\n' 'nginx version: {version}' >&2\n")
    path.chmod(0o755)
