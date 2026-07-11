from __future__ import annotations

import os
import shutil
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import run

APP_ICON_NAME = "AppIcon.icns"
APP_INFO_PLIST_NAME = "Info.plist"
APP_BRAND_IMAGE_NAME = "vitaldb.png"
PWA_APP_DIR = "apps/vitalserver-runtime-pwa"
PWA_DIST_DIR = "dist"
PWA_RESOURCE_DIR = "runtime-control-pwa"
PLATFORM_AGENT_PRODUCT_NAME = "vitalserver-platform-agent"


def sync_release(root: Path, runtime_dir: Path, release_file: Path) -> None:
    run(
        [
            "python3",
            str(runtime_dir / "Support/Build/sync-release.py"),
            str(runtime_dir),
            str(release_file),
        ],
        cwd=root,
    )


def build_swift(
    runtime_dir: Path,
    sdkroot: str | None,
    clang_module_cache: str,
    helper_product_name: str,
) -> None:
    env = os.environ.copy()
    if sdkroot:
        env["SDKROOT"] = sdkroot
    env["CLANG_MODULE_CACHE_PATH"] = clang_module_cache
    run(["swift", "build", "-c", "release"], cwd=runtime_dir, env=env)
    run(
        ["swift", "build", "-c", "release", "--product", helper_product_name],
        cwd=runtime_dir,
        env=env,
    )


def sign_runtime_cli(runtime_cli: Path, runtime_dir: Path, identity: str) -> None:
    sign_runtime_cli_with_entitlements(
        runtime_cli,
        runtime_dir / "Entitlements.shared.plist",
        identity,
    )


def sign_runtime_cli_with_entitlements(
    runtime_cli: Path,
    entitlements: Path,
    identity: str,
) -> None:
    run(
        [
            "codesign",
            "--force",
            "--sign",
            identity,
            "--entitlements",
            str(entitlements),
            str(runtime_cli),
        ]
    )


def build_app_bundle(
    *,
    root: Path,
    runtime_dir: Path,
    helper_bin: Path,
    app_bundle: Path,
    app_name: str,
    helper_version: str,
    codesign_identity: str,
) -> None:
    info_plist_source = runtime_dir / "Support/App" / APP_INFO_PLIST_NAME
    icon_source = runtime_dir / "Support/App" / APP_ICON_NAME
    brand_image_source = runtime_dir / "Support/App" / APP_BRAND_IMAGE_NAME
    pwa_dist_source = root / PWA_APP_DIR / PWA_DIST_DIR
    platform_agent_bin = helper_bin.parent / PLATFORM_AGENT_PRODUCT_NAME
    for required in [helper_bin, platform_agent_bin, info_plist_source, icon_source, brand_image_source]:
        if not required.is_file():
            raise SystemExit(f"error: missing app bundle input: {required}")
    if not (pwa_dist_source / "index.html").is_file():
        raise SystemExit(
            "error: missing Runtime Control PWA build output: "
            f"{pwa_dist_source}. Run: make pwa-build"
        )

    if app_bundle.exists():
        if app_bundle.is_symlink() or not app_bundle.is_dir():
            raise SystemExit(
                f"error: refusing to replace non-directory app bundle: {app_bundle}"
            )
        shutil.rmtree(app_bundle)
    contents = app_bundle / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copy2(helper_bin, macos / app_name)
    (macos / app_name).chmod(0o755)
    shutil.copy2(platform_agent_bin, macos / PLATFORM_AGENT_PRODUCT_NAME)
    (macos / PLATFORM_AGENT_PRODUCT_NAME).chmod(0o755)
    run(
        [
            "codesign",
            "--force",
            "--sign",
            codesign_identity,
            str(macos / PLATFORM_AGENT_PRODUCT_NAME),
        ],
        cwd=root,
    )
    info_plist = contents / APP_INFO_PLIST_NAME
    shutil.copy2(info_plist_source, info_plist)
    run(
        [
            "/usr/libexec/PlistBuddy",
            "-c",
            f"Set :CFBundleShortVersionString {helper_version}",
            str(info_plist),
        ]
    )
    shutil.copy2(icon_source, resources / APP_ICON_NAME)
    shutil.copy2(brand_image_source, resources / APP_BRAND_IMAGE_NAME)
    shutil.copytree(
        pwa_dist_source,
        resources / PWA_RESOURCE_DIR,
        ignore=shutil.ignore_patterns(".DS_Store", "._*"),
    )
    run(["codesign", "--force", "--sign", codesign_identity, str(app_bundle)], cwd=root)
