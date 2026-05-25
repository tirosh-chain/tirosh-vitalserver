from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_image.cloud_init import (
    create_cloud_init_seed as write_cloud_init_seed,
)
from tirosh_vitalserver.devtools.adapters.guest_image.cloud_init import (
    default_runtime_dir,
    default_ssh_key_path,
    generate_instance_id,
)
from tirosh_vitalserver.devtools.adapters.guest_image.cloud_init import (
    print_result as print_cloud_init_result,
)
from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    run_rootfs_base,
)
from tirosh_vitalserver.devtools.adapters.guest_image.ubuntu import (
    host_machine,
    run_ubuntu,
)
from tirosh_vitalserver.devtools.application.inputs import (
    CloudInitInput,
    RootfsBaseInput,
    UbuntuBootAssetsInput,
)
from tirosh_vitalserver.devtools.config.guest_image import (
    load_cloud_init_config,
    load_guest_runtime_config,
    load_ubuntu_image_config,
)
from tirosh_vitalserver.devtools.core.guest_image import (
    CloudInitSeedSpec,
    ubuntu_boot_asset_plan,
)


def prepare_ubuntu_boot_assets(
    input: UbuntuBootAssetsInput,
) -> int:
    config = load_config(input.config)
    ubuntu_config = load_ubuntu_image_config(config)
    runtime_config = load_guest_runtime_config(config)
    runtime_dir = (
        input.runtime_dir
        or runtime_config.runtime_dir
        or default_runtime_dir()
    )
    rootfs_size = input.rootfs_size or runtime_config.rootfs_size
    recreate_rootfs = (
        input.recreate_rootfs
        if input.recreate_rootfs is not None
        else runtime_config.recreate_rootfs
    )
    disk_image_name = input.disk_image_name or runtime_config.disk_image_name
    plan = ubuntu_boot_asset_plan(
        config_path=input.config,
        runtime_dir=runtime_dir,
        rootfs_size=rootfs_size,
        recreate_rootfs=recreate_rootfs,
        disk_image_name=disk_image_name,
        ubuntu_version=ubuntu_config.version,
        base_url=ubuntu_config.base_url,
        requested_arch=ubuntu_config.arch,
        host_machine=host_machine(),
        kernel_suffix=ubuntu_config.kernel_suffix,
        initrd_suffix=ubuntu_config.initrd_suffix,
    )
    return run_ubuntu(plan)


def create_cloud_init_seed(input: CloudInitInput) -> int:
    config = load_config(input.config)
    runtime_config = load_guest_runtime_config(config)
    cloud_config = load_cloud_init_config(config)

    runtime_dir = (
        input.runtime_dir
        or runtime_config.runtime_dir
        or default_runtime_dir()
    )
    seed_dir = input.seed_dir or runtime_dir / cloud_config.seed_directory_name
    seed_iso = input.seed_iso or runtime_dir / cloud_config.seed_iso_name
    hostname = input.hostname or cloud_config.hostname
    instance_id = input.instance_id or generate_instance_id()
    username = input.username or cloud_config.username
    password = input.password or cloud_config.password
    ssh_key_path = input.ssh_key or cloud_config.ssh_key_path or default_ssh_key_path()
    run_bootstrap = (
        input.run_bootstrap
        if input.run_bootstrap is not None
        else cloud_config.run_bootstrap
    )
    share_tag = input.share_tag or cloud_config.share_tag
    share_mount = input.share_mount or cloud_config.share_mount
    bootstrap_script = input.bootstrap_script or cloud_config.bootstrap_script

    write_cloud_init_seed(
        CloudInitSeedSpec(
            seed_dir=seed_dir,
            seed_iso=seed_iso,
            hostname=hostname,
            instance_id=instance_id,
            username=username,
            password=password,
            ssh_key_path=ssh_key_path,
            run_bootstrap=run_bootstrap,
            share_tag=share_tag,
            share_mount=share_mount,
            bootstrap_script=bootstrap_script,
        )
    )
    print_cloud_init_result(
        seed_iso,
        username,
        password,
        hostname,
        instance_id,
        run_bootstrap,
        bootstrap_script,
    )
    return 0


def compress_rootfs_base(input: RootfsBaseInput) -> int:
    return run_rootfs_base(input)
