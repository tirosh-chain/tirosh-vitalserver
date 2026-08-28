from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

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
from tirosh_vitalserver.devtools.application.inputs import (
    ApplySmokeReleaseUpdateBundleInput,
    NginxBundleInput,
    ReleaseUpdateBundleInput,
    VerifyReleaseUpdateBundleInput,
)
from tirosh_vitalserver.devtools.application.usecases.guest_services import (
    build_configured_docker_image_bundles,
)
from tirosh_vitalserver.devtools.application.usecases.host_proxy import (
    build_nginx as build_nginx_bundle,
)
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.config.release_manifest import load_release_manifest
from tirosh_vitalserver.devtools.core.guest_services import guest_deploy_plan
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_update_migrations,
    host_proxy_expected_version,
    release_update_bundle_name,
    release_update_components,
    require_rootfs_for_update,
)
from tirosh_vitalserver.devtools.core.update_bundle_models import (
    BuildUpdateBundleInput,
)

# The retained schema-3 publisher requires a SemVer field even though the
# stable bootstrap contract has no updater-version gate. Keep that legacy
# serialization detail out of the product release manifest.
LEGACY_SCHEMA3_NO_UPDATER_VERSION_GATE = "0.0.0"


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
            expected_version=host_proxy_expected_version(
                release=release,
                explicit_version=input.nginx_expected_version,
            ),
        )
    )
    optional_docker_bundle = build_configured_docker_image_bundles(
        root=root,
        config=input.config,
        runtime_dir=runtime_dir,
        bundle_path=settings.docker_bundle,
        platform=input.docker_platform,
        compression_threads=input.compression_threads,
        include_optional=False,
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
            optional_docker_bundle=optional_docker_bundle,
            include_optional=False,
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
            min_updater_version=LEGACY_SCHEMA3_NO_UPDATER_VERSION_GATE,
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
    bundle_path = release_update_bundle_path(
        config=input.config,
        release_file=input.release_file,
        bundle_name=input.bundle_name,
        bundle_kind=input.bundle_kind,
        output_dir=input.output_dir,
    )
    verify_bundle(bundle_path)
    print(
        "update bundle integrity checked; "
        f"publisher authenticity unverified: {bundle_path}"
    )
    return 0


def apply_smoke_update_bundle(input: ApplySmokeReleaseUpdateBundleInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    if release.channel != "dev":
        raise SystemExit(
            f"legacy {release.channel} update apply smoke is unavailable because "
            "trusted publisher verification is not implemented"
        )
    bundle_path = release_update_bundle_path(
        config=input.config,
        release_file=input.release_file,
        bundle_name=input.bundle_name,
        bundle_kind=input.bundle_kind,
        output_dir=input.output_dir,
    )
    vm_cli = Path(settings.install.vm_cli)
    if not bundle_path.is_file():
        raise SystemExit(f"missing update bundle for apply smoke: {bundle_path}")
    if not vm_cli.is_file() or not os.access(vm_cli, os.X_OK):
        raise SystemExit(
            f"installed runtime CLI is missing or not executable: {vm_cli}"
        )
    print(f"update apply smoke started bundle={bundle_path} cli={vm_cli}", flush=True)
    command = [
        "sudo",
        str(vm_cli),
        "runtime",
        "apply-bundle",
        str(bundle_path),
        "--allow-unsigned-dev-bundle",
    ]
    result = subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise SystemExit(
            f"update apply smoke failed exitCode={result.returncode}: "
            f"{' '.join(command)}. "
            "Run from an interactive administrator shell or configure sudo "
            "credentials before running dist/*/apply-smoke targets."
        )
    print(f"update apply smoke completed bundle={bundle_path}")
    return 0


def release_update_bundle_path(
    *,
    config: Path,
    release_file: Path,
    bundle_name: str | None,
    bundle_kind: str,
    output_dir: Path | None,
) -> Path:
    root = repo_root()
    settings = load_macos_release_settings(config, root)
    resolved_release_file = resolve_path(root, release_file)
    release = load_release_manifest(resolved_release_file)
    bundle_name = release_update_bundle_name(
        channel=release.channel,
        bundle_kind=bundle_kind,
        release_label=release.release_label,
        explicit_name=bundle_name,
    )
    output_dir = (
        resolve_path(root, output_dir)
        if output_dir
        else settings.dist_dir / "update-bundles"
    )
    return output_dir / f"{bundle_name}.tar.gz"
