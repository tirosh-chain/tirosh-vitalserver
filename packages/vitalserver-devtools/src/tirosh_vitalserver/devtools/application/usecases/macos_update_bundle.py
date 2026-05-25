from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_services.docker_images import (
    build_docker_image_bundle as run_docker_image_bundle,
)
from tirosh_vitalserver.devtools.adapters.macos_release.runtime_app import (
    build_app_bundle,
    build_swift,
    sign_runtime_cli,
    sync_release,
)
from tirosh_vitalserver.devtools.adapters.macos_release.update_artifacts import (
    stage_update_artifacts,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.adapters.update_bundle.bundle_service import (
    build_bundle,
    verify_bundle,
)
from tirosh_vitalserver.devtools.application.guest_service_plans import (
    docker_image_bundle_build_plan,
)
from tirosh_vitalserver.devtools.application.inputs import (
    NginxBundleInput,
    ReleaseUpdateBundleInput,
    VerifyReleaseUpdateBundleInput,
)
from tirosh_vitalserver.devtools.application.usecases.host_proxy import (
    build_nginx as build_nginx_bundle,
)
from tirosh_vitalserver.devtools.config.docker_images import load_docker_images_config
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.config.release_manifest import load_release_manifest
from tirosh_vitalserver.devtools.core.guest_services import guest_deploy_plan
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_update_migrations,
    release_update_bundle_name,
    release_update_components,
    require_rootfs_for_update,
)
from tirosh_vitalserver.devtools.core.update_bundle_models import (
    BuildUpdateBundleInput,
)


def build_update_bundle(input: ReleaseUpdateBundleInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    bundle_kind = input.bundle_kind
    bundle_name = release_update_bundle_name(
        channel=release.channel,
        bundle_kind=bundle_kind,
        release_label=release.release_label,
        explicit_name=input.bundle_name,
    )
    clang_module_cache = input.clang_module_cache or str(settings.clang_module_cache)

    sync_release(root, runtime_dir, release_file)
    build_swift(
        runtime_dir,
        input.sdkroot,
        clang_module_cache,
        settings.helper_product_name,
    )
    sign_runtime_cli(
        settings.runtime_cli,
        runtime_dir,
        input.codesign_identity,
    )
    build_app_bundle(
        root=root,
        runtime_dir=runtime_dir,
        helper_bin=settings.helper_bin,
        app_bundle=settings.app_bundle,
        app_name=settings.app_name,
        helper_version=release.helper_version,
        codesign_identity=input.codesign_identity,
    )
    build_nginx_bundle(
        NginxBundleInput(
            config=input.config,
            bundle_dir=settings.nginx_bundle,
            binary=input.nginx_binary,
            expected_version=input.nginx_expected_version,
        )
    )
    build_docker_image_bundle_from_config(
        root=root,
        config=input.config,
        bundle_path=settings.docker_bundle,
        platform=input.docker_platform,
        compression_threads=input.compression_threads,
    )

    deploy_dir = settings.update_artifact_dir / "deploy"
    staged = stage_update_artifacts(
        runtime_dir=runtime_dir,
        settings=settings,
        artifact_dir=settings.update_artifact_dir,
        app_bundle=settings.app_bundle,
        runtime_cli=settings.runtime_cli,
        nginx_bundle=settings.nginx_bundle,
        guest_deploy_plan=guest_deploy_plan(
            root=root,
            runtime_dir=runtime_dir,
            deploy_dir=deploy_dir,
            vm_home=settings.update_artifact_dir,
            config=settings.guest_deploy,
            docker_bundle=settings.docker_bundle,
        ),
    )
    rootfs_base = resolve_path(root, input.rootfs_base) if input.rootfs_base else None
    require_rootfs_for_update(bundle_kind, rootfs_base)

    output_dir = (
        resolve_path(root, input.output_dir)
        if input.output_dir
        else settings.dist_dir / "update-bundles"
    )
    migrations = [resolve_path(root, migration) for migration in input.migration]
    if not migrations:
        migrations = default_update_migrations(runtime_dir)
    build_bundle(
        BuildUpdateBundleInput(
            version=release.release_label,
            runtime_version=None,
            bundle_name=bundle_name,
            channel=release.channel,
            release_label=release.release_label,
            min_updater_version=release.minimum_updater_version,
            bundle_kind=bundle_kind,
            helper_version=release.helper_version,
            target_platform=input.target_platform or release.target_platform,
            component=release_update_components(
                helper_version=release.helper_version,
                vitalserver_version=release.vitalserver_version,
            ),
            requires_guest_activation=True,
            requires_two_phase_update=input.requires_two_phase_update,
            output_dir=output_dir,
            rootfs_base=rootfs_base,
            app_bundle=staged.app_bundle,
            runtime_tools=staged.runtime_tools,
            nginx_bundle=staged.nginx_bundle,
            guest_deploy=staged.guest_deploy,
            migration=migrations,
        )
    )
    print(f"release update bundle is ready: {output_dir / f'{bundle_name}.tar.gz'}")
    return 0


def verify_update_bundle(input: VerifyReleaseUpdateBundleInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    bundle_name = release_update_bundle_name(
        channel=release.channel,
        bundle_kind=input.bundle_kind,
        release_label=release.release_label,
        explicit_name=input.bundle_name,
    )
    output_dir = (
        resolve_path(root, input.output_dir)
        if input.output_dir
        else settings.dist_dir / "update-bundles"
    )
    bundle_path = output_dir / f"{bundle_name}.tar.gz"
    verify_bundle(bundle_path)
    print(f"update bundle verified: {bundle_path}")
    return 0


def build_docker_image_bundle_from_config(
    *,
    root: Path,
    config: Path,
    bundle_path: Path,
    platform: str | None,
    compression_threads: int | None,
) -> int:
    build_config = load_config(config)
    docker_config = load_docker_images_config(build_config, root)
    plan = docker_image_bundle_build_plan(
        root=root,
        docker_config=docker_config,
        bundle_path=bundle_path,
        platform=platform,
        compression_threads=compression_threads,
    )
    return run_docker_image_bundle(
        plan=plan.image_plan,
        bundle_path=plan.bundle_path,
        compression_threads_value=plan.compression_threads,
    )
