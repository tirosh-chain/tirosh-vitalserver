from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    TomlTable,
    nested_section,
    optional_bool,
    optional_string,
    required_string,
)
from tirosh_vitalserver.devtools.core.guest_image import (
    CloudInitConfig,
    GuestRuntimeConfig,
    UbuntuImageConfig,
)


def load_guest_runtime_config(config: TomlTable) -> GuestRuntimeConfig:
    path = "guest.runtime"
    runtime = nested_section(config, path)
    return GuestRuntimeConfig(
        runtime_dir=Path(
            required_string(runtime, "runtime_dir", path=path)
        ).expanduser(),
        rootfs_size=optional_string(runtime, "rootfs_size", "4G", path=path),
        recreate_rootfs=optional_bool(runtime, "recreate_rootfs", False, path=path),
        disk_image_name=optional_string(
            runtime,
            "disk_image_name",
            "vm-disk.img",
            path=path,
        ),
    )


def load_ubuntu_image_config(config: TomlTable) -> UbuntuImageConfig:
    path = "guest.ubuntu"
    ubuntu = nested_section(config, path)
    return UbuntuImageConfig(
        version=required_string(ubuntu, "version", path=path),
        base_url=required_string(ubuntu, "base_url", path=path),
        arch=optional_string(ubuntu, "arch", "auto", path=path),
        kernel_suffix=optional_string(
            ubuntu,
            "kernel_suffix",
            "vmlinuz-generic",
            path=path,
        ),
        initrd_suffix=optional_string(
            ubuntu,
            "initrd_suffix",
            "initrd-generic",
            path=path,
        ),
    )


def load_cloud_init_config(config: TomlTable) -> CloudInitConfig:
    path = "guest.cloud_init"
    cloud_init = nested_section(config, path)
    return CloudInitConfig(
        seed_directory_name=optional_string(
            cloud_init,
            "seed_directory_name",
            "cloud-init-seed",
            path=path,
        ),
        seed_iso_name=optional_string(
            cloud_init,
            "seed_iso_name",
            "seed.iso",
            path=path,
        ),
        hostname=optional_string(
            cloud_init,
            "hostname",
            "tirosh-vitalserver",
            path=path,
        ),
        username=optional_string(cloud_init, "username", "ubuntu", path=path),
        password=optional_string(cloud_init, "password", "ubuntu", path=path),
        ssh_key_path=Path(
            optional_string(
                cloud_init,
                "ssh_key_path",
                "~/.ssh/id_ed25519.pub",
                path=path,
            )
        ).expanduser(),
        run_bootstrap=optional_bool(cloud_init, "run_bootstrap", True, path=path),
        share_tag=optional_string(cloud_init, "share_tag", "tirosh", path=path),
        share_mount=optional_string(
            cloud_init,
            "share_mount",
            "/mnt/tirosh",
            path=path,
        ),
        bootstrap_script=optional_string(
            cloud_init,
            "bootstrap_script",
            "/mnt/tirosh/deploy/bootstrap.sh",
            path=path,
        ),
    )
