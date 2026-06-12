from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    ensure_vm_data_dirs,
    stage_guest_deploy,
)
from tirosh_vitalserver.devtools.adapters.guest_services.docker_images import (
    build_docker_image_bundle as run_docker_image_bundle,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.guest_service_plans import (
    docker_image_bundle_build_plan,
)
from tirosh_vitalserver.devtools.application.inputs import (
    DockerImageBundleInput,
    GuestDeploymentInput,
)
from tirosh_vitalserver.devtools.config.docker_images import load_docker_images_config
from tirosh_vitalserver.devtools.config.guest_deploy import (
    load_guest_deploy_config,
)
from tirosh_vitalserver.devtools.config.guest_image import load_ubuntu_image_config
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.core.guest_image import ubuntu_download_cache_key
from tirosh_vitalserver.devtools.core.guest_services import (
    guest_deploy_plan,
)


def build_docker_image_bundle(
    input: DockerImageBundleInput,
) -> int:
    root = repo_root()
    config = load_config(input.config)
    docker_config = load_docker_images_config(config, root)
    plan = docker_image_bundle_build_plan(
        root=root,
        docker_config=docker_config,
        bundle_path=input.bundle_path,
        platform=input.platform,
        compression_threads=input.compression_threads,
    )
    run_docker_image_bundle(
        plan=plan.image_plan,
        bundle_path=plan.bundle_path,
        compression_threads_value=plan.compression_threads,
    )
    if docker_config.optional_images and docker_config.optional_bundle_path is not None:
        optional_config = replace(docker_config, images=docker_config.optional_images)
        optional_plan = docker_image_bundle_build_plan(
            root=root,
            docker_config=optional_config,
            bundle_path=docker_config.optional_bundle_path,
            platform=input.platform,
            compression_threads=input.compression_threads,
        )
        run_docker_image_bundle(
            plan=optional_plan.image_plan,
            bundle_path=optional_plan.bundle_path,
            compression_threads_value=optional_plan.compression_threads,
        )
    return 0


def stage_guest_deployment(
    input: GuestDeploymentInput,
) -> int:
    root = repo_root()
    config = load_config(input.config)
    deploy_config = load_guest_deploy_config(config)
    runtime_dir = resolve_path(root, input.runtime_dir)
    vm_home = resolve_path(root, input.vm_home)
    deploy_dir = (
        resolve_path(root, input.deploy_dir)
        if input.deploy_dir is not None
        else vm_home / "data/deploy"
    )
    docker_bundle = (
        resolve_path(root, input.docker_bundle)
        if input.docker_bundle is not None
        else None
    )
    docker_config = load_docker_images_config(config, root)
    optional_docker_bundle = (
        docker_config.optional_bundle_path
        if (
            docker_config.optional_bundle_path
            and docker_config.optional_bundle_path.is_file()
        )
        else None
    )

    plan = guest_deploy_plan(
        root=root,
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        vm_home=vm_home,
        config=deploy_config,
        docker_bundle=docker_bundle,
        optional_docker_bundle=optional_docker_bundle,
    )
    stage_guest_deploy(plan)
    ubuntu_config = load_ubuntu_image_config(config)
    stage_rootfs_input_metadata(
        deploy_dir=deploy_dir,
        base_url=ubuntu_config.base_url,
        apt_snapshot=ubuntu_config.apt_snapshot,
        run_id=input.rootfs_run_id,
    )
    ensure_vm_data_dirs(plan)
    print(f"guest deployment bundle is ready: {deploy_dir}")
    return 0


def stage_rootfs_input_metadata(
    *,
    deploy_dir: Path,
    base_url: str,
    apt_snapshot: str,
    run_id: str | None = None,
) -> None:
    metadata = deploy_dir / "build-metadata" / "rootfs-input.json"
    metadata.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "schemaVersion": 1,
        "runtimeBootSmoke": {
            "enabled": False,
        },
        "ubuntu": {
            "aptSnapshot": apt_snapshot,
            "baseUrl": base_url,
            "cacheKey": ubuntu_download_cache_key(base_url),
        },
    }
    if run_id:
        document["runId"] = run_id
    metadata.write_text(
        json.dumps(document, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
