from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    stage_guest_deploy,
    stage_rootfs_input_metadata,
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

ROOTFS_BASE_NAME = "rootfs-base.raw.gz"
RESET_INSTALLER_CLI_NAME = "vitalserver-vm-reset-installer"
RESET_TROUBLESHOOTING_CLI_NAME = "vitalserver-troubleshooting-reset-for-reinstall"
RESET_INSTALLER_COMMAND_NAME = "Reset VitalServer Helper for Reinstall.command"
UPSTREAM_REDIS_SAVE_CLI_NAME = "vitalserver-troubleshooting-upstream-redis-save"
UPSTREAM_REDIS_BACKUP_COMMAND_NAME = "Create Upstream Redis Backup.command"


@dataclass(frozen=True)
class DmgAttachment:
    mount_point: Path
    device_entry: str | None


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
    stage_troubleshooting_tools(
        settings=context.settings,
        runtime_dir=context.runtime_dir,
        runtime_cli=context.runtime_cli,
        tools_dir=staging / "Troubleshooting Tools",
    )
    install_file(
        context.pkg_output,
        staging / package_output_value(context, "dmg_installer_pkg_name"),
    )
    context.dmg_output.parent.mkdir(parents=True, exist_ok=True)
    detach_unmounted_dmg_output_attachments(context.dmg_output)
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


def detach_unmounted_dmg_output_attachments(dmg_output: Path) -> None:
    attached = attached_disk_images()
    expected_path = str(dmg_output.resolve(strict=False))
    for image in attached:
        image_path = image.get("image-path")
        if not isinstance(image_path, str):
            continue
        if str(Path(image_path).resolve(strict=False)) != expected_path:
            continue
        mount_points = attached_image_mount_points(image)
        if not mount_points:
            detach_attached_image_without_mount(
                image=image,
                expected_path=expected_path,
            )
            continue
        mount_description = ", ".join(mount_points)
        raise RuntimeError(
            "DMG output is currently attached; detach it before rebuilding: "
            f"{expected_path} ({mount_description})"
        )


def detach_attached_image_without_mount(
    *,
    image: dict[str, object],
    expected_path: str,
) -> None:
    device_entry = attached_image_device_entry(image)
    if device_entry is None:
        raise RuntimeError(
            "DMG output is attached without a mount point, but hdiutil did not "
            f"report a device entry to detach: {expected_path}"
        )
    run(["hdiutil", "detach", device_entry])


def ensure_dmg_output_is_not_attached(dmg_output: Path) -> None:
    detach_unmounted_dmg_output_attachments(dmg_output)


def hdiutil_verify_image(dmg_output: Path) -> None:
    result = subprocess.run(
        ["hdiutil", "verify", str(dmg_output)],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode == 0:
        return
    detail = "\n".join(
        line
        for line in [result.stdout.strip(), result.stderr.strip()]
        if line
    )
    raise RuntimeError(detail or f"hdiutil verify exited {result.returncode}")


def attach_dmg_readonly(dmg_output: Path) -> DmgAttachment:
    result = subprocess.run(
        [
            "hdiutil",
            "attach",
            "-plist",
            "-readonly",
            "-nobrowse",
            str(dmg_output),
        ],
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace").strip()
        raise RuntimeError(stderr or f"hdiutil attach exited {result.returncode}")
    document = plistlib.loads(result.stdout)
    images = document.get("system-entities") if isinstance(document, dict) else None
    if not isinstance(images, list):
        raise RuntimeError("hdiutil attach did not return system-entities")
    mount_point: Path | None = None
    device_entry: str | None = None
    for entity in images:
        if not isinstance(entity, dict):
            continue
        if device_entry is None:
            dev_entry = entity.get("dev-entry")
            if isinstance(dev_entry, str) and dev_entry:
                device_entry = dev_entry
        raw_mount_point = entity.get("mount-point")
        if isinstance(raw_mount_point, str) and raw_mount_point:
            mount_point = Path(raw_mount_point)
            break
    if mount_point is None:
        if device_entry:
            run(["hdiutil", "detach", device_entry])
        raise RuntimeError("hdiutil attach did not report a mount point")
    return DmgAttachment(mount_point=mount_point, device_entry=device_entry)


def detach_dmg_attachment(attachment: DmgAttachment) -> None:
    target = str(attachment.mount_point)
    if not attachment.mount_point.exists() and attachment.device_entry:
        target = attachment.device_entry
    run(["hdiutil", "detach", target])


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


def attached_image_device_entry(image: dict[str, object]) -> str | None:
    entities = image.get("system-entities")
    if not isinstance(entities, list):
        return None
    for entity in entities:
        if not isinstance(entity, dict):
            continue
        dev_entry = entity.get("dev-entry")
        if isinstance(dev_entry, str) and dev_entry:
            return dev_entry
    return None


def stage_reset_installer_command(
    *,
    settings: MacOSReleaseSettings,
    runtime_dir: Path,
    runtime_cli: Path,
    tools_dir: Path,
) -> None:
    tools_dir.mkdir(parents=True, exist_ok=True)
    bin_dir = tools_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    packaging_dir = runtime_dir / "Support/Packaging"
    copy_executable(runtime_cli, bin_dir / RESET_INSTALLER_CLI_NAME)
    copy_executable(
        runtime_cli.parent / RESET_TROUBLESHOOTING_CLI_NAME,
        bin_dir / RESET_TROUBLESHOOTING_CLI_NAME,
    )
    render_packaging_executable(
        settings,
        packaging_dir / "reset-for-reinstall-command.template",
        tools_dir / RESET_INSTALLER_COMMAND_NAME,
    )


def stage_upstream_redis_backup_command(
    *,
    settings: MacOSReleaseSettings,
    runtime_dir: Path,
    upstream_redis_save_cli: Path,
    tools_dir: Path,
) -> None:
    tools_dir.mkdir(parents=True, exist_ok=True)
    bin_dir = tools_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    packaging_dir = runtime_dir / "Support/Packaging"
    copy_executable(upstream_redis_save_cli, bin_dir / UPSTREAM_REDIS_SAVE_CLI_NAME)
    render_packaging_executable(
        settings,
        packaging_dir / "upstream-redis-backup-command.template",
        tools_dir / UPSTREAM_REDIS_BACKUP_COMMAND_NAME,
    )


def stage_troubleshooting_tools(
    *,
    settings: MacOSReleaseSettings,
    runtime_dir: Path,
    runtime_cli: Path,
    tools_dir: Path,
) -> None:
    if tools_dir.exists():
        shutil.rmtree(tools_dir)
    tools_dir.mkdir(parents=True, exist_ok=True)
    stage_reset_installer_command(
        settings=settings,
        runtime_dir=runtime_dir,
        runtime_cli=runtime_cli,
        tools_dir=tools_dir,
    )
    stage_upstream_redis_backup_command(
        settings=settings,
        runtime_dir=runtime_dir,
        upstream_redis_save_cli=runtime_cli.parent / UPSTREAM_REDIS_SAVE_CLI_NAME,
        tools_dir=tools_dir,
    )
    remove_apple_double_files(tools_dir)
    subprocess.run(["xattr", "-c", "-r", str(tools_dir)], check=False)


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
    stage_rootfs_input_metadata(context.rootfs_input_metadata_plan)
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
