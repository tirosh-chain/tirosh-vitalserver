from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_app import (
    build_app_bundle,
    build_swift,
    sync_release,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import MacOSAppInput
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.config.release_manifest import load_release_manifest


def build_helper(input: MacOSAppInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    clang_module_cache = input.clang_module_cache or str(settings.clang_module_cache)

    sync_release(root, settings.runtime_dir, release_file)
    build_swift(
        settings.runtime_dir,
        input.sdkroot,
        clang_module_cache,
        settings.helper_product_name,
    )
    build_app_bundle(
        root=root,
        runtime_dir=settings.runtime_dir,
        helper_bin=settings.helper_bin,
        app_bundle=settings.app_bundle,
        app_name=settings.app_name,
        helper_version=release.helper_version,
        codesign_identity=input.codesign_identity,
    )
    print(f"macOS app bundle is ready: {settings.app_bundle}")
    return 0
