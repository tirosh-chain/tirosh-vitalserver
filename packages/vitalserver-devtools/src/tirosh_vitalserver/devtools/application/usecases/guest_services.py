from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    require_rootfs_artifact_guest_deploy_match,
)
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    ensure_vm_data_dirs,
    stage_guest_deploy,
    stage_materialized_guest_deploy,
)
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    stage_rootfs_input_metadata as write_rootfs_input_metadata,
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
from tirosh_vitalserver.devtools.config.guest_image import (
    load_guest_runtime_config,
    load_ubuntu_image_config,
)
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.core.guest_image import RuntimeDataDiskConfig
from tirosh_vitalserver.devtools.core.guest_services import (
    DockerImagePlan,
    RootfsInputMetadataPlan,
    guest_compose_contract_errors,
    guest_deploy_plan,
)


def build_docker_image_bundle(
    input: DockerImageBundleInput,
) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    build_configured_docker_image_bundles(
        root=root,
        config=input.config,
        runtime_dir=settings.runtime_dir,
        bundle_path=input.bundle_path,
        platform=input.platform,
        compression_threads=input.compression_threads,
        include_optional=True,
    )
    return 0


def build_configured_docker_image_bundles(
    *,
    root: Path,
    config: Path,
    runtime_dir: Path,
    bundle_path: Path | None,
    platform: str | None,
    compression_threads: int | None,
    include_optional: bool,
) -> Path | None:
    build_config = load_config(config)
    docker_config = load_docker_images_config(build_config, root)
    deploy_config = load_guest_deploy_config(build_config)
    plan = docker_image_bundle_build_plan(
        root=root,
        docker_config=docker_config,
        bundle_path=bundle_path,
        platform=platform,
        compression_threads=compression_threads,
    )
    require_guest_compose_compile_contract(
        root=root,
        runtime_dir=runtime_dir,
        image_plan=plan.image_plan,
        known_images=set(docker_config.images) | set(docker_config.optional_images),
        deploy_include_sources=[
            entry.source
            for entry in (
                [*deploy_config.includes, *deploy_config.optional_includes]
                if include_optional
                else deploy_config.includes
            )
        ],
        optional_images=set(docker_config.optional_images),
        include_optional=include_optional,
    )
    run_docker_image_bundle(
        plan=plan.image_plan,
        bundle_path=plan.bundle_path,
        compression_threads_value=plan.compression_threads,
    )
    if (
        not include_optional
        or not docker_config.optional_images
        or docker_config.optional_bundle_path is None
    ):
        return None

    optional_config = replace(docker_config, images=docker_config.optional_images)
    optional_plan = docker_image_bundle_build_plan(
        root=root,
        docker_config=optional_config,
        bundle_path=docker_config.optional_bundle_path,
        platform=platform,
        compression_threads=compression_threads,
    )
    run_docker_image_bundle(
        plan=optional_plan.image_plan,
        bundle_path=optional_plan.bundle_path,
        compression_threads_value=optional_plan.compression_threads,
    )
    return optional_plan.bundle_path


def require_guest_compose_compile_contract(
    *,
    root: Path,
    runtime_dir: Path,
    image_plan: DockerImagePlan,
    known_images: set[str],
    deploy_include_sources: list[Path],
    optional_images: set[str],
    include_optional: bool,
) -> None:
    compose_path = runtime_dir / "Support/Guest/compose.yaml"
    try:
        compose_text = compose_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise SystemExit(
            "error: Guest compose compile contract is unreadable: "
            f"{compose_path}: {error}"
        ) from error
    errors = guest_compose_contract_errors(
        root=root,
        compose_text=compose_text,
        image_plan=image_plan,
        known_images=known_images,
        deploy_include_sources=deploy_include_sources,
        optional_images=optional_images,
        include_optional=include_optional,
    )
    if errors:
        raise SystemExit(
            "error: Guest compose compile contract failed:\n"
            + "\n".join(f"- {error}" for error in errors)
        )


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
        include_optional=optional_docker_bundle is not None,
    )
    if input.source_deploy_dir is None:
        stage_guest_deploy(plan)
    else:
        stage_materialized_guest_deploy(
            resolve_path(root, input.source_deploy_dir),
            deploy_dir,
        )
    ubuntu_config = load_ubuntu_image_config(config)
    runtime_config = load_guest_runtime_config(config)
    stage_rootfs_input_metadata(
        deploy_dir=deploy_dir,
        base_url=ubuntu_config.base_url,
        apt_snapshot=ubuntu_config.apt_snapshot,
        runtime_data=runtime_config.runtime_data_disk,
        docker_platform=docker_config.platform,
        run_id=input.rootfs_run_id,
        runtime_boot_smoke_run_id=input.runtime_boot_smoke_run_id,
    )
    if input.rootfs_artifact is not None:
        require_rootfs_artifact_guest_deploy_match(
            resolve_path(root, input.rootfs_artifact),
            deploy_dir,
        )
    ensure_vm_data_dirs(plan)
    print(f"guest deployment bundle is ready: {deploy_dir}")
    return 0


def stage_rootfs_input_metadata(
    *,
    deploy_dir: Path,
    base_url: str,
    apt_snapshot: str,
    runtime_data: RuntimeDataDiskConfig,
    docker_platform: str,
    run_id: str | None = None,
    runtime_boot_smoke_run_id: str | None = None,
) -> None:
    write_rootfs_input_metadata(
        RootfsInputMetadataPlan(
            deploy_dir=deploy_dir,
            base_url=base_url,
            apt_snapshot=apt_snapshot,
            runtime_data=runtime_data,
            docker_platform=docker_platform,
            run_id=run_id,
            runtime_boot_smoke_run_id=runtime_boot_smoke_run_id,
        )
    )
