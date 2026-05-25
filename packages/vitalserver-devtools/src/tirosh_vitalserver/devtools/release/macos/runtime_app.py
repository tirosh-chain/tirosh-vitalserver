from __future__ import annotations

import os
import shutil
from pathlib import Path

from tirosh_vitalserver.devtools.toolchain.shell_commands import run

APP_ICON_NAME = "AppIcon.icns"
APP_INFO_PLIST_NAME = "Info.plist"


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
    if app_bundle.exists():
        shutil.rmtree(app_bundle)
    contents = app_bundle / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copy2(helper_bin, macos / app_name)
    (macos / app_name).chmod(0o755)
    info_plist = contents / APP_INFO_PLIST_NAME
    shutil.copy2(runtime_dir / "Support/App" / APP_INFO_PLIST_NAME, info_plist)
    run(
        [
            "/usr/libexec/PlistBuddy",
            "-c",
            f"Set :CFBundleShortVersionString {helper_version}",
            str(info_plist),
        ]
    )
    shutil.copy2(runtime_dir / "Support/App" / APP_ICON_NAME, resources / APP_ICON_NAME)
    run(["codesign", "--force", "--sign", codesign_identity, str(app_bundle)], cwd=root)
