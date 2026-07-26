from __future__ import annotations

import subprocess

from tirosh_vitalserver.devtools.adapters.guest_image.ubuntu import qemu_image_info
from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import (
    require_tool,
    run,
)
from tirosh_vitalserver.devtools.core.guest_image import (
    RuntimeDataDiskPlan,
    size_to_bytes,
)


def prepare_ephemeral_runtime_data_disk(plan: RuntimeDataDiskPlan) -> dict[str, object]:
    require_tool("qemu-img", "Install it on the build machine with: brew install qemu")
    plan.runtime_dir.mkdir(parents=True, exist_ok=True)

    removed = False
    if plan.disk_image.exists():
        plan.disk_image.unlink()
        removed = True

    print(
        "Preparing ephemeral runtime data disk: "
        f"{plan.disk_image} ({plan.disk_size}, label={plan.filesystem_label})"
    )
    run([
        "qemu-img",
        "create",
        "-f",
        "raw",
        str(plan.disk_image),
        plan.disk_size,
    ])
    validate_runtime_data_disk(plan)
    return {
        "path": str(plan.disk_image),
        "diskImageName": plan.disk_image_name,
        "diskSize": plan.disk_size,
        "filesystemLabel": plan.filesystem_label,
        "mountPath": plan.mount_path,
        "dockerDataRoot": plan.docker_data_root,
        "containerdRoot": plan.containerd_root,
        "removedStaleDisk": removed,
    }


def validate_runtime_data_disk(plan: RuntimeDataDiskPlan) -> None:
    try:
        info = qemu_image_info(plan.disk_image, label="runtime data disk")
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        raise SystemExit(
            f"error: invalid runtime data disk: qemu-img info failed for "
            f"{plan.disk_image}: {error}"
        ) from error
    image_format = info.get("format")
    virtual_size = info.get("virtual-size")
    expected_size = size_to_bytes(plan.disk_size)
    if image_format != "raw":
        raise SystemExit(
            "error: invalid runtime data disk: "
            f"{plan.disk_image}: expected raw image, got {image_format!r}"
        )
    if not isinstance(virtual_size, int) or virtual_size != expected_size:
        raise SystemExit(
            "error: invalid runtime data disk size: "
            f"{plan.disk_image}: virtual-size={virtual_size!r} expected={expected_size}"
        )
