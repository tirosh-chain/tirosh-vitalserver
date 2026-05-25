from __future__ import annotations

import shutil
from argparse import Namespace
from pathlib import Path

from tirosh_vitalserver.devtools.config.macos.release_settings import (
    MacOSReleaseSettings,
    load_macos_release_settings,
    resolve_path,
)
from tirosh_vitalserver.devtools.config.release_manifest import (
    ReleaseManifest,
    load_release_manifest,
)
from tirosh_vitalserver.devtools.guest_services.docker_images import run_docker_images
from tirosh_vitalserver.devtools.host_proxy.nginx_bundle import run_nginx_bundle
from tirosh_vitalserver.devtools.release.macos.artifact_names import format_release_name
from tirosh_vitalserver.devtools.release.macos.installer_package import (
    build_dmg,
    build_pkg,
)
from tirosh_vitalserver.devtools.release.macos.models import PackageContext
from tirosh_vitalserver.devtools.release.macos.runtime_app import (
    build_app_bundle,
    build_swift,
    sign_runtime_cli,
    sync_release,
)
from tirosh_vitalserver.devtools.release.macos.update_artifacts import (
    stage_update_artifacts,
)
from tirosh_vitalserver.devtools.toolchain.shell_commands import run
from tirosh_vitalserver.devtools.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.update_bundle import (
    run_build_update_bundle,
    run_verify_update_bundle,
)

DEFAULT_UPDATE_MIGRATIONS = (
    "001-refresh-cloud-init-seed",
    "002-migrate-runtime-logs",
)


def run_macos_app(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    release_file = resolve_path(root, args.release_file)
    release = load_release_manifest(release_file)
    clang_module_cache = args.clang_module_cache or str(settings.clang_module_cache)

    sync_release(root, settings.runtime_dir, release_file)
    build_swift(
        settings.runtime_dir,
        args.sdkroot,
        clang_module_cache,
        settings.helper_product_name,
    )
    build_app_bundle(
        root=root,
        runtime_dir=settings.runtime_dir,
        helper_bin=settings.helper_bin,
        app_bundle=settings.app_bundle,
        app_name=settings.app_name,
        helper_version=release.helper_version,
        codesign_identity=args.codesign_identity,
    )
    print(f"macOS app bundle is ready: {settings.app_bundle}")
    return 0


def run_release_update_bundle(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, args.release_file)
    release = load_release_manifest(release_file)
    bundle_kind = args.bundle_kind
    release_label = release.release_label
    channel = release.channel
    helper_version = release.helper_version
    min_updater_version = release.minimum_updater_version
    target_platform = release.target_platform
    artifact_dir = settings.update_artifact_dir
    app_bundle = settings.app_bundle
    runtime_cli = settings.runtime_cli
    helper_bin = settings.helper_bin
    nginx_bundle = settings.nginx_bundle
    docker_bundle = settings.docker_bundle
    bundle_name = (
        args.bundle_name or f"update-bundle-{channel}-{bundle_kind}-{release_label}"
    )
    clang_module_cache = args.clang_module_cache or str(settings.clang_module_cache)

    sync_release(root, runtime_dir, release_file)
    build_swift(
        runtime_dir,
        args.sdkroot,
        clang_module_cache,
        settings.helper_product_name,
    )
    sign_runtime_cli(runtime_cli, runtime_dir, args.codesign_identity)
    build_app_bundle(
        root=root,
        runtime_dir=runtime_dir,
        helper_bin=helper_bin,
        app_bundle=app_bundle,
        app_name=settings.app_name,
        helper_version=helper_version,
        codesign_identity=args.codesign_identity,
    )
    run_nginx_bundle(
        Namespace(
            config=args.config,
            bundle_dir=nginx_bundle,
            binary=args.nginx_binary,
            expected_version=args.nginx_expected_version,
        )
    )
    run_docker_images(
        Namespace(
            config=args.config,
            bundle_path=docker_bundle,
            platform=args.docker_platform,
            compression_threads=args.compression_threads,
        )
    )

    staged = stage_update_artifacts(
        root=root,
        runtime_dir=runtime_dir,
        settings=settings,
        artifact_dir=artifact_dir,
        app_bundle=app_bundle,
        runtime_cli=runtime_cli,
        nginx_bundle=nginx_bundle,
        docker_bundle=docker_bundle,
    )
    rootfs_base = resolve_path(root, args.rootfs_base) if args.rootfs_base else None
    if bundle_kind == "vm-image-update" and rootfs_base is None:
        raise SystemExit("error: --rootfs-base is required for vm-image-update")

    output_dir = (
        resolve_path(root, args.output_dir)
        if args.output_dir
        else settings.dist_dir / "update-bundles"
    )
    migrations = [resolve_path(root, migration) for migration in args.migration]
    if not migrations:
        migrations = default_update_migrations(runtime_dir)
    run_build_update_bundle(
        Namespace(
            version=release_label,
            runtime_version=None,
            bundle_name=bundle_name,
            channel=channel,
            release_label=release_label,
            min_updater_version=min_updater_version,
            bundle_kind=bundle_kind,
            helper_version=helper_version,
            target_platform=args.target_platform or target_platform,
            component=[
                f"helperUI={helper_version}+macos.1",
                f"updater={helper_version}",
                f"supervisor={helper_version}",
                f"vmDriver={helper_version}+macos.1",
                f"serviceStack={release.vitalserver_version}-stack.1",
                f"vitalServer={release.vitalserver_version}",
            ],
            requires_guest_activation=True,
            requires_two_phase_update=args.requires_two_phase_update,
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


def run_release_update_bundle_verify(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    release_file = resolve_path(root, args.release_file)
    release = load_release_manifest(release_file)
    bundle_kind = args.bundle_kind
    bundle_name = (
        args.bundle_name
        or f"update-bundle-{release.channel}-{bundle_kind}-{release.release_label}"
    )
    bundle_path = settings.dist_dir / "update-bundles" / f"{bundle_name}.tar.gz"
    return run_verify_update_bundle(Namespace(bundle_path=bundle_path))


def run_release_pkg(args: Namespace) -> int:
    context = prepare_package_context(args)
    build_pkg(context)
    print(f"release pkg is ready: {context.pkg_output}")
    return 0


def run_release_dmg(args: Namespace) -> int:
    context = prepare_package_context(args)
    build_pkg(context)
    build_dmg(context)
    print(f"release dmg is ready: {context.dmg_output}")
    return 0


def run_macos_package_clean(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    release_file = resolve_path(root, args.release_file)
    release = load_release_manifest(release_file)
    paths = [
        settings.pkg_root.parent,
        default_pkg_output(settings, release),
        settings.app_bundle,
        default_dmg_output(settings, release),
    ]
    for path in paths:
        if path.exists():
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
    return 0


def run_macos_package_install(args: Namespace) -> int:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    release_file = resolve_path(root, args.release_file)
    release = load_release_manifest(release_file)
    pkg_output = default_pkg_output(settings, release)
    if not pkg_output.is_file():
        raise SystemExit(
            f"missing {pkg_output}. Run: make vm-pkg-dev or make vm-pkg-release"
        )
    if args.install_settings:
        install_settings = resolve_path(root, args.install_settings)
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


def prepare_package_context(args: Namespace) -> PackageContext:
    root = repo_root()
    settings = load_macos_release_settings(args.config, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, args.release_file)
    release = load_release_manifest(release_file)
    helper_version = release.helper_version
    if args.output:
        pkg_output = resolve_path(root, args.output)
    elif args.output_kind == "dmg":
        pkg_output = default_dmg_output(settings, release)
    else:
        pkg_output = default_pkg_output(settings, release)
    dmg_output = pkg_output
    if pkg_output.suffix == ".dmg":
        pkg_output = settings.dist_dir / format_release_name(
            settings.outputs.pkg_filename_template,
            release,
        )
    else:
        dmg_output = settings.dist_dir / format_release_name(
            settings.outputs.dmg_filename_template,
            release,
        )

    app_bundle = settings.app_bundle
    runtime_cli = settings.runtime_cli
    helper_bin = settings.helper_bin
    nginx_bundle = settings.nginx_bundle
    docker_bundle = settings.docker_bundle

    sync_release(root, runtime_dir, release_file)
    clang_module_cache = args.clang_module_cache or str(settings.clang_module_cache)
    build_swift(
        runtime_dir,
        args.sdkroot,
        clang_module_cache,
        settings.helper_product_name,
    )
    sign_runtime_cli(runtime_cli, runtime_dir, args.codesign_identity)
    build_app_bundle(
        root=root,
        runtime_dir=runtime_dir,
        helper_bin=helper_bin,
        app_bundle=app_bundle,
        app_name=settings.app_name,
        helper_version=helper_version,
        codesign_identity=args.codesign_identity,
    )
    run_nginx_bundle(
        Namespace(
            config=args.config,
            bundle_dir=nginx_bundle,
            binary=args.nginx_binary,
            expected_version=args.nginx_expected_version,
        )
    )
    run_docker_images(
        Namespace(
            config=args.config,
            bundle_path=docker_bundle,
            platform=args.docker_platform,
            compression_threads=args.compression_threads,
        )
    )

    return PackageContext(
        root=root,
        runtime_dir=runtime_dir,
        release=release,
        pkg_root=settings.pkg_root,
        pkg_scripts=settings.pkg_scripts,
        pkg_output=pkg_output,
        dmg_output=dmg_output,
        app_bundle=app_bundle,
        runtime_cli=runtime_cli,
        nginx_bundle=nginx_bundle,
        docker_bundle=docker_bundle,
        rootfs_base=resolve_path(root, args.rootfs_base),
        golden_runtime_dir=resolve_path(root, args.golden_runtime_dir),
        proxy_port=args.proxy_port,
        settings=settings,
    )


def default_pkg_output(
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
) -> Path:
    return settings.dist_dir / format_release_name(
        settings.outputs.pkg_filename_template,
        release,
    )


def default_dmg_output(
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
) -> Path:
    return settings.dist_dir / format_release_name(
        settings.outputs.dmg_filename_template,
        release,
    )


def default_update_migrations(runtime_dir: Path) -> list[Path]:
    migrations_dir = runtime_dir / "Support/Build/migrations"
    return [migrations_dir / name for name in DEFAULT_UPDATE_MIGRATIONS]
