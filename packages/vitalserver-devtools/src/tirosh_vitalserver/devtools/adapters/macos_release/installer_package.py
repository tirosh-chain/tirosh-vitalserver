from __future__ import annotations

import os
import plistlib
import shutil
import signal
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    require_rootfs_artifact_guest_deploy_match,
    rootfs_artifact_manifest_path,
)
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    stage_materialized_guest_deploy,
    stage_rootfs_input_metadata,
)
from tirosh_vitalserver.devtools.adapters.macos_release.artifact_files import (
    copy_executable,
    copy_tree,
    install_file,
    remove_apple_double_files,
    remove_staging_tree,
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
DMG_PROCESS_INSPECTION_TIMEOUT_SECONDS = 10
DMG_OUTPUT_RELEASE_GRACE_ATTEMPTS = 40
DMG_OUTPUT_TERMINATE_ATTEMPTS = 8
DMG_OUTPUT_KILL_ATTEMPTS = 8
DMG_OUTPUT_RELEASE_POLL_SECONDS = 0.25


@dataclass(frozen=True)
class DmgAttachment:
    mount_point: Path
    device_entry: str | None


@dataclass(frozen=True)
class DmgOutputHolder:
    pid: int
    parent_pid: int
    executable: Path
    open_dmg_paths: tuple[Path, ...]


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
        remove_staging_tree(staging)
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
    release_orphaned_dmg_output_helpers(context.dmg_output)


def release_orphaned_dmg_output_helpers(
    dmg_output: Path,
    *,
    grace_attempts: int = DMG_OUTPUT_RELEASE_GRACE_ATTEMPTS,
    terminate_attempts: int = DMG_OUTPUT_TERMINATE_ATTEMPTS,
    kill_attempts: int = DMG_OUTPUT_KILL_ATTEMPTS,
    poll_seconds: float = DMG_OUTPUT_RELEASE_POLL_SECONDS,
) -> None:
    holders = wait_for_dmg_output_release(
        dmg_output,
        attempts=grace_attempts,
        poll_seconds=poll_seconds,
    )
    if not holders:
        return
    require_owned_orphaned_dmg_helpers(dmg_output, holders)
    pids = sorted(holder.pid for holder in holders)
    print(
        "DMG output remains open after hdiutil completed; terminating owned "
        f"orphaned diskimages-helper processes: output={dmg_output} pids={pids}"
    )
    signal_dmg_output_holders(holders, signal.SIGTERM)
    holders = wait_for_dmg_output_release(
        dmg_output,
        attempts=terminate_attempts,
        poll_seconds=poll_seconds,
    )
    if not holders:
        return
    require_owned_orphaned_dmg_helpers(dmg_output, holders)
    pids = sorted(holder.pid for holder in holders)
    print(
        "Owned orphaned diskimages-helper processes ignored SIGTERM; sending "
        f"SIGKILL: output={dmg_output} pids={pids}"
    )
    signal_dmg_output_holders(holders, signal.SIGKILL)
    holders = wait_for_dmg_output_release(
        dmg_output,
        attempts=kill_attempts,
        poll_seconds=poll_seconds,
    )
    if holders:
        raise RuntimeError(
            "DMG output remains open after terminating owned orphaned helpers: "
            f"output={dmg_output} holders={format_dmg_output_holders(holders)}"
        )


def wait_for_dmg_output_release(
    dmg_output: Path,
    *,
    attempts: int,
    poll_seconds: float,
) -> list[DmgOutputHolder]:
    if attempts < 1:
        raise ValueError("DMG output release attempts must be at least one")
    for attempt in range(attempts):
        holders = dmg_output_holders(dmg_output)
        if not holders:
            return []
        if attempt + 1 < attempts:
            time.sleep(poll_seconds)
    return holders


def dmg_output_holders(dmg_output: Path) -> list[DmgOutputHolder]:
    lsof_path = shutil.which("lsof")
    ps_path = shutil.which("ps")
    if lsof_path is None or ps_path is None:
        missing = [
            name
            for name, path in [("lsof", lsof_path), ("ps", ps_path)]
            if path is None
        ]
        raise RuntimeError(
            "required tools are unavailable while inspecting DMG output holders: "
            + ", ".join(missing)
        )
    expected_path = dmg_output.resolve(strict=False)
    result = run_inspection_command(
        [lsof_path, "-nP", "-t", "--", str(expected_path)],
        description=f"processes holding DMG output {expected_path}",
    )
    if (
        result.returncode == 1
        and not result.stdout.strip()
        and not result.stderr.strip()
    ):
        return []
    if result.returncode != 0:
        detail = (
            result.stderr.strip() or result.stdout.strip() or str(result.returncode)
        )
        raise RuntimeError(
            f"failed to inspect processes holding DMG output {expected_path}: {detail}"
        )
    raw_pids = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not raw_pids or any(not raw_pid.isdecimal() for raw_pid in raw_pids):
        raise RuntimeError(
            "lsof returned malformed DMG output holder PIDs: "
            f"output={expected_path} stdout={result.stdout!r}"
        )
    holders: list[DmgOutputHolder] = []
    for pid in sorted({int(raw_pid) for raw_pid in raw_pids}):
        holder = inspect_dmg_output_holder(
            pid=pid,
            expected_path=expected_path,
            lsof_path=lsof_path,
            ps_path=ps_path,
        )
        if holder is not None:
            holders.append(holder)
    return holders


def inspect_dmg_output_holder(
    *,
    pid: int,
    expected_path: Path,
    lsof_path: str,
    ps_path: str,
) -> DmgOutputHolder | None:
    process = run_inspection_command(
        [ps_path, "-p", str(pid), "-o", "ppid=", "-o", "comm="],
        description=f"DMG output holder process {pid}",
    )
    if process.returncode != 0:
        if not process.stdout.strip() and not process.stderr.strip():
            return None
        detail = process.stderr.strip() or process.stdout.strip()
        raise RuntimeError(f"failed to inspect DMG output holder pid={pid}: {detail}")
    fields = process.stdout.strip().split(maxsplit=1)
    if len(fields) != 2 or not fields[0].isdecimal() or not fields[1]:
        raise RuntimeError(
            "ps returned malformed DMG output holder metadata: "
            f"pid={pid} stdout={process.stdout!r}"
        )
    open_files = run_inspection_command(
        [lsof_path, "-nP", "-p", str(pid), "-Fn"],
        description=f"open files for DMG output holder {pid}",
    )
    if open_files.returncode != 0:
        if not open_files.stdout.strip() and not open_files.stderr.strip():
            return None
        detail = open_files.stderr.strip() or open_files.stdout.strip()
        raise RuntimeError(
            f"failed to inspect open files for DMG output holder pid={pid}: {detail}"
        )
    open_dmg_paths = tuple(
        sorted(
            {
                Path(line[1:]).resolve(strict=False)
                for line in open_files.stdout.splitlines()
                if line.startswith("n") and line[1:].endswith(".dmg")
            },
            key=str,
        )
    )
    if expected_path not in open_dmg_paths:
        return None
    return DmgOutputHolder(
        pid=pid,
        parent_pid=int(fields[0]),
        executable=Path(fields[1]),
        open_dmg_paths=open_dmg_paths,
    )


def run_inspection_command(
    command: list[str],
    *,
    description: str,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=False,
            text=True,
            capture_output=True,
            timeout=DMG_PROCESS_INSPECTION_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            f"timed out inspecting {description} after "
            f"{DMG_PROCESS_INSPECTION_TIMEOUT_SECONDS} seconds"
        ) from error
    except OSError as error:
        raise RuntimeError(f"failed to inspect {description}: {error}") from error


def require_owned_orphaned_dmg_helpers(
    dmg_output: Path,
    holders: list[DmgOutputHolder],
) -> None:
    expected_path = dmg_output.resolve(strict=False)
    unsafe = [
        holder
        for holder in holders
        if holder.parent_pid != 1
        or holder.executable.name != "diskimages-helper"
        or holder.open_dmg_paths != (expected_path,)
    ]
    if unsafe:
        raise RuntimeError(
            "DMG output remains open; refusing to signal a process whose ownership "
            "is not limited to the exact build output: "
            f"output={expected_path} holders={format_dmg_output_holders(unsafe)}"
        )


def signal_dmg_output_holders(
    holders: list[DmgOutputHolder],
    requested_signal: int,
) -> None:
    for holder in holders:
        try:
            os.kill(holder.pid, requested_signal)
        except ProcessLookupError:
            continue
        except OSError as error:
            raise RuntimeError(
                "failed to signal owned orphaned DMG output helper: "
                f"pid={holder.pid} signal={requested_signal} error={error}"
            ) from error


def format_dmg_output_holders(holders: list[DmgOutputHolder]) -> str:
    return "; ".join(
        "pid="
        f"{holder.pid} parentPid={holder.parent_pid} "
        f"executable={holder.executable} "
        "openDmgPaths="
        f"{','.join(str(path) for path in holder.open_dmg_paths)}"
        for holder in holders
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
    detach_hdiutil_target(device_entry)


def ensure_dmg_output_is_not_attached(dmg_output: Path) -> None:
    detach_unmounted_dmg_output_attachments(dmg_output)


def hdiutil_verify_image(dmg_output: Path) -> None:
    release_orphaned_dmg_output_helpers(dmg_output)
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


def expand_pkg_payload(package: Path, destination: Path) -> Path:
    result = subprocess.run(
        ["pkgutil", "--expand-full", str(package), str(destination)],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = "\n".join(
            line
            for line in [result.stdout.strip(), result.stderr.strip()]
            if line
        )
        raise RuntimeError(detail or f"pkgutil expand exited {result.returncode}")
    payload = destination / "Payload"
    if not payload.is_dir():
        raise RuntimeError(
            "pkgutil expanded package without a materialized Payload directory: "
            f"{package}"
        )
    return payload


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
    target = attachment.device_entry or str(attachment.mount_point)
    detach_hdiutil_target(target)


def detach_hdiutil_target(target: str) -> None:
    try:
        run(["hdiutil", "detach", target])
    except subprocess.CalledProcessError as first_error:
        try:
            run(["hdiutil", "detach", "-force", target])
        except subprocess.CalledProcessError as force_error:
            raise RuntimeError(
                "failed to detach DMG attachment "
                f"{target}: detach exited {first_error.returncode}; "
                f"force detach exited {force_error.returncode}"
            ) from force_error


def attached_disk_images() -> list[dict[str, object]]:
    try:
        result = subprocess.run(
            ["hdiutil", "info", "-plist"],
            check=False,
            capture_output=True,
            timeout=DMG_PROCESS_INSPECTION_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            "failed to read attached disk images: hdiutil info timed out after "
            f"{DMG_PROCESS_INSPECTION_TIMEOUT_SECONDS} seconds"
        ) from error
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
        remove_staging_tree(tools_dir)
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
    rootfs_manifest = rootfs_artifact_manifest_path(context.rootfs_base)
    required = [
        image,
        initrd,
        context.rootfs_base,
        rootfs_manifest,
    ]
    for required_input in required:
        if not required_input.is_file():
            raise SystemExit(f"error: missing package input: {required_input}")
    if not context.guest_deploy_source.is_dir():
        raise SystemExit(
            "error: missing compiled Guest deploy package input: "
            f"{context.guest_deploy_source}"
        )

    if context.pkg_root.exists():
        remove_staging_tree(context.pkg_root)
    if context.pkg_scripts.exists():
        remove_staging_tree(context.pkg_scripts)

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
        rootfs_manifest,
        package_path(
            context,
            f"{install_home(context)}/runtime/{rootfs_manifest.name}",
        ),
    )
    install_file(
        context.root / "infra/macos-nginx/vitalserver.conf.template",
        package_path(
            context,
            f"{install_home(context)}/Support/Proxy/vitalserver.conf.template",
        ),
    )
    package_deploy_dir = package_path(context, f"{install_home(context)}/data/deploy")
    stage_materialized_guest_deploy(
        context.guest_deploy_source,
        package_deploy_dir,
    )
    stage_rootfs_input_metadata(context.rootfs_input_metadata_plan)
    require_rootfs_artifact_guest_deploy_match(
        context.rootfs_base,
        package_deploy_dir,
    )
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
