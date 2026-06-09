from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    stage_guest_deploy,
)
from tirosh_vitalserver.devtools.adapters.macos_release.artifact_files import (
    copy_executable,
    copy_tree,
    install_file,
    remove_apple_double_files,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_templates import (
    plist_text,
    render_launchd_templates,
    render_packaging_executable,
    render_packaging_template,
)
from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import run
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    install_app_bundle,
    install_home,
    install_nginx_prefix,
    package_install_value,
    package_output_value,
    package_path,
)
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.settings import (
    MacOSReleaseSettings,
)
from tirosh_vitalserver.devtools.core.release_manifest import ReleaseManifest

ROOTFS_BASE_NAME = "rootfs-base.raw.gz"
RESET_INSTALLER_IDENTIFIER_SUFFIX = ".reset-installer"
RESET_INSTALLER_CLI_NAME = "vitalserver-vm-reset-installer"


def build_pkg(context: PackageContext) -> None:
    stage_pkg_root(context)
    context.pkg_output.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "pkgbuild",
            "--root",
            str(context.pkg_root),
            "--component-plist",
            str(context.settings.pkg_component_plist),
            "--scripts",
            str(context.pkg_scripts),
            "--filter",
            r"\.DS_Store$",
            "--filter",
            r"/CVS$",
            "--filter",
            r"/\.svn$",
            "--filter",
            r".*\._.*",
            "--identifier",
            context.settings.package_identifier,
            "--version",
            context.release.helper_version,
            "--install-location",
            "/",
            str(context.pkg_output),
        ],
        env={**os.environ, "COPYFILE_DISABLE": "1"},
    )


def build_dmg(context: PackageContext) -> None:
    staging = context.settings.dmg_staging_dir
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    build_reset_installer_pkg(
        settings=context.settings,
        release=context.release,
        runtime_dir=context.runtime_dir,
        runtime_cli=context.runtime_cli,
        scripts_dir=context.pkg_root.parent / "reset-installer-scripts",
        pkg_output=context.clean_uninstaller_pkg_output,
    )
    install_file(
        context.pkg_output,
        staging / package_output_value(context, "dmg_installer_pkg_name"),
    )
    install_file(
        context.clean_uninstaller_pkg_output,
        staging / package_output_value(context, "dmg_clean_uninstaller_pkg_name"),
    )
    context.dmg_output.parent.mkdir(parents=True, exist_ok=True)
    ensure_dmg_output_is_not_attached(context.dmg_output)
    if context.dmg_output.exists():
        context.dmg_output.unlink()
    run(
        [
            "hdiutil",
            "create",
            "-volname",
            context.settings.app_name,
            "-srcfolder",
            str(staging),
            "-ov",
            "-format",
            "UDZO",
            str(context.dmg_output),
        ]
    )


def ensure_dmg_output_is_not_attached(dmg_output: Path) -> None:
    attached = attached_disk_images()
    expected_path = str(dmg_output.resolve(strict=False))
    for image in attached:
        image_path = image.get("image-path")
        if not isinstance(image_path, str):
            continue
        if str(Path(image_path).resolve(strict=False)) != expected_path:
            continue
        mount_points = attached_image_mount_points(image)
        mount_description = ", ".join(mount_points) if mount_points else "not mounted"
        raise RuntimeError(
            "DMG output is currently attached; detach it before rebuilding: "
            f"{expected_path} ({mount_description})"
        )


def attached_disk_images() -> list[dict[str, object]]:
    result = subprocess.run(
        ["hdiutil", "info", "-plist"],
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace").strip()
        raise RuntimeError(
            "failed to read attached disk images: "
            f"{stderr or result.returncode}"
        )
    document = plistlib.loads(result.stdout)
    images = document.get("images") if isinstance(document, dict) else None
    if not isinstance(images, list):
        raise RuntimeError("hdiutil info did not return an images array")
    return [image for image in images if isinstance(image, dict)]


def attached_image_mount_points(image: dict[str, object]) -> list[str]:
    entities = image.get("system-entities")
    if not isinstance(entities, list):
        return []
    mount_points: list[str] = []
    for entity in entities:
        if not isinstance(entity, dict):
            continue
        mount_point = entity.get("mount-point")
        if isinstance(mount_point, str) and mount_point:
            mount_points.append(mount_point)
    return mount_points


def build_reset_installer_pkg(
    *,
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
    runtime_dir: Path,
    runtime_cli: Path,
    scripts_dir: Path,
    pkg_output: Path,
) -> None:
    if scripts_dir.exists():
        shutil.rmtree(scripts_dir)
    scripts_dir.mkdir(parents=True, exist_ok=True)
    pkg_output.parent.mkdir(parents=True, exist_ok=True)
    if pkg_output.exists():
        pkg_output.unlink()

    packaging_dir = runtime_dir / "Support/Packaging"
    copy_executable(runtime_cli, scripts_dir / RESET_INSTALLER_CLI_NAME)
    render_packaging_executable(
        settings,
        packaging_dir / "clean-uninstall-postinstall.template",
        scripts_dir / "postinstall",
    )
    remove_apple_double_files(scripts_dir)
    subprocess.run(["xattr", "-c", "-r", str(scripts_dir)], check=False)
    run(
        [
            "pkgbuild",
            "--nopayload",
            "--scripts",
            str(scripts_dir),
            "--filter",
            r"\.DS_Store$",
            "--filter",
            r".*\._.*",
            "--identifier",
            f"{settings.package_identifier}{RESET_INSTALLER_IDENTIFIER_SUFFIX}",
            "--version",
            release.helper_version,
            str(pkg_output),
        ],
        env={
            **os.environ,
            "COPYFILE_DISABLE": "1",
            "COPY_EXTENDED_ATTRIBUTES_DISABLE": "1",
        },
    )


def stage_pkg_root(context: PackageContext) -> None:
    image = context.golden_runtime_dir / "Image"
    initrd = context.golden_runtime_dir / "initrd.img"
    for required in [image, initrd, context.rootfs_base, context.docker_bundle]:
        if not required.is_file():
            raise SystemExit(f"error: missing package input: {required}")

    if context.pkg_root.exists():
        shutil.rmtree(context.pkg_root)
    if context.pkg_scripts.exists():
        shutil.rmtree(context.pkg_scripts)

    mkdirs = [
        package_path(context, package_install_value(context, "applications_dir")),
        package_path(
            context,
            Path(package_install_value(context, "vm_cli")).parent.as_posix(),
        ),
        package_path(context, f"{install_home(context)}/runtime"),
        package_path(context, f"{install_home(context)}/data/deploy"),
        package_path(context, f"{install_home(context)}/Support/Proxy"),
        package_path(context, install_nginx_prefix(context)),
        package_path(
            context,
            package_install_value(context, "launch_daemons_dir"),
        ),
        context.pkg_scripts,
    ]
    for directory in mkdirs:
        directory.mkdir(parents=True, exist_ok=True)

    install_file(
        context.runtime_cli,
        package_path(context, package_install_value(context, "vm_cli")),
    )
    run(
        [
            "codesign",
            "--force",
            "--sign",
            "-",
            "--entitlements",
            str(context.runtime_dir / "Entitlements.shared.plist"),
            str(package_path(context, package_install_value(context, "vm_cli"))),
        ]
    )
    assert_virtualization_entitlement(
        package_path(context, package_install_value(context, "vm_cli"))
    )

    packaging_dir = context.runtime_dir / "Support/Packaging"
    render_packaging_executable(
        context.settings,
        packaging_dir / "proxy-run.template",
        package_path(context, package_install_value(context, "proxy_runner")),
    )
    render_packaging_executable(
        context.settings,
        packaging_dir / "uninstall.template",
        package_path(context, package_install_value(context, "uninstaller")),
    )
    copy_tree(context.app_bundle, package_path(context, install_app_bundle(context)))
    copy_tree(
        context.nginx_bundle,
        package_path(context, install_nginx_prefix(context)),
    )
    install_file(image, package_path(context, f"{install_home(context)}/runtime/Image"))
    install_file(
        initrd,
        package_path(context, f"{install_home(context)}/runtime/initrd.img"),
    )
    install_file(
        context.rootfs_base,
        package_path(context, f"{install_home(context)}/runtime/{ROOTFS_BASE_NAME}"),
    )
    install_file(
        context.root / "infra/macos-nginx/vitalserver.conf.template",
        package_path(
            context,
            f"{install_home(context)}/Support/Proxy/vitalserver.conf.template",
        ),
    )
    stage_guest_deploy(context.guest_deploy_plan)
    render_launchd_templates(context)
    copy_executable(packaging_dir / "preinstall", context.pkg_scripts / "preinstall")
    copy_executable(
        context.runtime_cli,
        context.pkg_scripts / "vitalserver-vm-preinstall",
    )
    render_packaging_executable(
        context.settings,
        packaging_dir / "postinstall.template",
        context.pkg_scripts / "postinstall",
    )
    render_packaging_template(
        context.settings,
        packaging_dir / "components.plist.template",
        context.settings.pkg_component_plist,
        {
            "APP_BUNDLE_ROOT_RELATIVE": plist_text(
                install_app_bundle(context).strip("/")
            ),
        },
    )
    remove_apple_double_files(context.pkg_root)
    remove_apple_double_files(context.pkg_scripts)
    subprocess.run(["xattr", "-rc", str(context.pkg_root)], check=False)


def assert_virtualization_entitlement(binary: Path) -> None:
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(binary)],
        check=False,
        text=True,
        capture_output=True,
    )
    entitlement = "com.apple.security.virtualization"
    if entitlement not in f"{result.stdout}{result.stderr}":
        raise SystemExit(f"error: packaged binary is missing {entitlement}: {binary}")
