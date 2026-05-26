from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_services.docker_images import (
    build_docker_image_bundle as run_docker_image_bundle,
)
from tirosh_vitalserver.devtools.adapters.macos_release.artifact_files import (
    remove_path,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    build_dmg as run_build_dmg,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    build_pkg as run_build_pkg,
)
from tirosh_vitalserver.devtools.adapters.macos_release.runtime_app import (
    build_app_bundle,
    build_swift,
    sign_runtime_cli,
    sync_release,
)
from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import run
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.guest_service_plans import (
    docker_image_bundle_build_plan,
)
from tirosh_vitalserver.devtools.application.inputs import (
    MacOSPackageCleanInput,
    MacOSPackageInstallInput,
    NginxBundleInput,
    ReleasePackageInput,
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
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    settings_install_home,
)
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_pkg_output,
    host_proxy_expected_version,
    package_clean_plan,
    package_outputs,
)


def build_pkg(input: ReleasePackageInput) -> int:
    context = prepare_package_context(input)
    run_build_pkg(context)
    print(f"release pkg is ready: {context.pkg_output}")
    return 0


def build_dmg(input: ReleasePackageInput) -> int:
    context = prepare_package_context(input)
    run_build_pkg(context)
    run_build_dmg(context)
    print(f"release dmg is ready: {context.dmg_output}")
    return 0


def clean_package(input: MacOSPackageCleanInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    plan = package_clean_plan(root=root, settings=settings, release=release)
    for path in plan.paths:
        if path.exists():
            remove_path(path)
    return 0


def install_pkg(input: MacOSPackageInstallInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    pkg_output = default_pkg_output(settings, release)
    if not pkg_output.is_file():
        raise SystemExit(
            f"missing {pkg_output}. Run: make vm-pkg-dev or make vm-pkg-release"
        )
    if input.install_settings:
        install_settings = resolve_path(
            root,
            input.install_settings,
        )
        if not install_settings.is_file():
            raise SystemExit(f"missing {install_settings}")
        run(
            [
                "sudo",
                "install",
                "-m",
                "0600",
                str(install_settings),
                settings.install.install_settings_json,
            ]
        )
        print(f"installed runtime settings: {settings.install.install_settings_json}")
    run(["sudo", "installer", "-pkg", str(pkg_output), "-target", "/"])
    return 0


def prepare_package_context(input: ReleasePackageInput) -> PackageContext:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    outputs = package_outputs(
        settings=settings,
        release=release,
        requested_output=resolve_path(root, input.output) if input.output else None,
        output_kind=input.output_kind,
    )

    sync_release(root, runtime_dir, release_file)
    clang_module_cache = input.clang_module_cache or str(settings.clang_module_cache)
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
    build_docker_image_bundle_from_config(
        root=root,
        config=input.config,
        bundle_path=settings.docker_bundle,
        platform=input.docker_platform,
        compression_threads=input.compression_threads,
    )
    package_vm_home = settings.pkg_root / settings_install_home(settings).strip("/")

    return PackageContext(
        root=root,
        runtime_dir=runtime_dir,
        release=release,
        pkg_root=settings.pkg_root,
        pkg_scripts=settings.pkg_scripts,
        pkg_output=outputs.pkg_output,
        dmg_output=outputs.dmg_output,
        app_bundle=settings.app_bundle,
        runtime_cli=settings.runtime_cli,
        nginx_bundle=settings.nginx_bundle,
        docker_bundle=settings.docker_bundle,
        rootfs_base=resolve_path(root, input.rootfs_base),
        golden_runtime_dir=resolve_path(root, input.golden_runtime_dir),
        guest_deploy_plan=guest_deploy_plan(
            root=root,
            runtime_dir=runtime_dir,
            deploy_dir=package_vm_home / "data/deploy",
            vm_home=package_vm_home,
            config=settings.guest_deploy,
            docker_bundle=settings.docker_bundle,
        ),
        proxy_port=input.proxy_port,
        settings=settings,
    )


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
