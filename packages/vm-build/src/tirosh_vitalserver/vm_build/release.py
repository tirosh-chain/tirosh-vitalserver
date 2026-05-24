from __future__ import annotations

import json
import os
import shutil
import subprocess
import tarfile
from argparse import Namespace
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

from .config import load_config, required_string, section
from .docker_images import run_docker_images
from .nginx_bundle import run_nginx_bundle
from .paths import repo_root
from .process import run
from .render_template import run_render_template
from .update_bundle import run_build_update_bundle

RUNTIME_CLI_NAME = "vitalserver-vm"
APP_ICON_NAME = "AppIcon.icns"
APP_INFO_PLIST_NAME = "Info.plist"
ROOTFS_BASE_NAME = "rootfs-base.raw.gz"


def run_release_update_bundle(args: Namespace) -> int:
    root = repo_root()
    settings = load_release_settings(args, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, args.release_file)
    release = load_release(release_file)
    bundle_kind = args.bundle_kind
    release_label = release["releaseLabel"]
    channel = release["channel"]
    helper_version = release["helperVersion"]
    min_updater_version = release["minUpdaterVersion"]
    artifact_dir = settings.update_artifact_dir
    app_bundle = settings.app_bundle
    runtime_cli = settings.runtime_cli
    helper_bin = settings.helper_bin
    nginx_bundle = settings.nginx_bundle
    docker_bundle = settings.docker_bundle
    bundle_name = (
        args.bundle_name
        or f"update-bundle-{channel}-{bundle_kind}-{release_label}"
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

    output_dir = resolve_path(root, args.output_dir)
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
            target_platform=[args.target_platform or settings.target_platform],
            component=[
                f"helperUI={helper_version}+macos.1",
                f"updater={helper_version}",
                f"supervisor={helper_version}",
                f"vmDriver={helper_version}+macos.1",
                f"serviceStack={release['vitalServerVersion']}-stack.1",
                f"vitalServer={release['vitalServerVersion']}",
            ],
            requires_guest_activation=True,
            requires_two_phase_update=args.requires_two_phase_update,
            output_dir=output_dir,
            rootfs_base=rootfs_base,
            app_bundle=staged.app_bundle,
            runtime_tools=staged.runtime_tools,
            nginx_bundle=staged.nginx_bundle,
            guest_deploy=staged.guest_deploy,
            migration=[resolve_path(root, migration) for migration in args.migration],
        )
    )
    print(f"release update bundle is ready: {output_dir / f'{bundle_name}.tar.gz'}")
    return 0


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


class StagedUpdateArtifacts(Namespace):
    app_bundle: Path
    runtime_tools: Path
    nginx_bundle: Path
    guest_deploy: Path


class ReleaseSettings(Namespace):
    config: dict[str, dict[str, object]]
    runtime_dir: Path
    helper_product_name: str
    app_name: str
    app_bundle: Path
    clang_module_cache: Path
    runtime_cli: Path
    helper_bin: Path
    nginx_bundle: Path
    docker_bundle: Path
    update_artifact_dir: Path
    pkg_build_dir: Path
    pkg_root: Path
    pkg_scripts: Path
    pkg_component_plist: Path
    dmg_staging_dir: Path
    dist_dir: Path
    target_platform: str
    package: dict[str, object]
    package_install: dict[str, object]
    package_outputs: dict[str, object]
    guest_deploy: dict[str, object]
    launchd: dict[str, object]


class PackageContext(Namespace):
    root: Path
    runtime_dir: Path
    release: dict[str, object]
    pkg_root: Path
    pkg_scripts: Path
    pkg_output: Path
    dmg_output: Path
    app_bundle: Path
    runtime_cli: Path
    nginx_bundle: Path
    docker_bundle: Path
    rootfs_base: Path
    golden_runtime_dir: Path
    proxy_port: str
    settings: ReleaseSettings


class PathMapping(Namespace):
    source: Path
    destination: Path


def load_release(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise SystemExit(f"error: missing release manifest: {path}")
    release = json.loads(path.read_text(encoding="utf-8"))
    required = [
        "channel",
        "helperVersion",
        "releaseLabel",
        "minUpdaterVersion",
        "vitalServerVersion",
    ]
    for key in required:
        if not isinstance(release.get(key), str) or not release[key]:
            raise SystemExit(f"error: missing release field: {key}")
    return release


def resolve_path(root: Path, value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def load_release_settings(args: Namespace, root: Path) -> ReleaseSettings:
    config = load_config(args.config)
    workspace = section(config, "workspace")
    app = section(config, "app")
    release_config = section(config, "release")
    package = section(config, "package")
    package_install = section(package, "install")
    package_outputs = section(package, "outputs")
    runtime_dir = resolve_path(root, required_string(workspace, "runtime_dir"))
    build_dir = resolve_path(root, required_string(workspace, "build_dir"))
    app_name = required_string(app, "name")
    helper_product_name = required_string(app, "helper_product_name")
    return ReleaseSettings(
        config=config,
        runtime_dir=runtime_dir,
        helper_product_name=helper_product_name,
        app_name=app_name,
        app_bundle=resolve_path(
            root,
            required_string(app, "bundle_dir"),
        ),
        clang_module_cache=resolve_path(
            root,
            required_string(workspace, "clang_module_cache"),
        ),
        runtime_cli=runtime_dir / ".build/release" / RUNTIME_CLI_NAME,
        helper_bin=runtime_dir / ".build/release" / helper_product_name,
        nginx_bundle=build_dir / "nginx-bundle",
        docker_bundle=resolve_path(
            root,
            required_string(section(config, "docker_images"), "bundle_path"),
        ),
        update_artifact_dir=build_dir / "update-artifacts",
        pkg_build_dir=build_dir,
        pkg_root=build_dir / "root",
        pkg_scripts=build_dir / "scripts",
        pkg_component_plist=build_dir / "components.plist",
        dmg_staging_dir=resolve_path(
            root,
            required_string(package_outputs, "dmg_staging_dir"),
        ),
        dist_dir=resolve_path(root, required_string(workspace, "dist_dir")),
        target_platform=required_string(release_config, "target_platform"),
        package=package,
        package_install=package_install,
        package_outputs=package_outputs,
        guest_deploy=section(config, "guest_deploy"),
        launchd=section(config, "launchd"),
    )


def prepare_package_context(args: Namespace) -> PackageContext:
    root = repo_root()
    settings = load_release_settings(args, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, args.release_file)
    release = load_release(release_file)
    helper_version = str(release["helperVersion"])
    pkg_output = resolve_path(root, args.output)
    dmg_output = pkg_output
    if pkg_output.suffix == ".dmg":
        pkg_output = settings.dist_dir / format_release_name(
            required_string(settings.package_outputs, "pkg_name_template"),
            release,
        )
    else:
        dmg_output = settings.dist_dir / format_release_name(
            required_string(settings.package_outputs, "dmg_name_template"),
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


def format_release_name(template: str, release: dict[str, object]) -> str:
    return template.format(
        helperVersion=release["helperVersion"],
        releaseLabel=release["releaseLabel"],
        channel=release["channel"],
    )


def required_path_mappings(
    config: dict[str, dict[str, object]],
    key: str,
) -> list[PathMapping]:
    value = config.get(key)
    if not isinstance(value, list) or not value:
        raise SystemExit(f"error: missing path mapping list: {key}")
    mappings = []
    for item in value:
        if not isinstance(item, dict):
            raise SystemExit(f"error: invalid path mapping: {key}")
        source = item.get("source")
        destination = item.get("destination")
        if not isinstance(source, str) or not isinstance(destination, str):
            raise SystemExit(f"error: invalid path mapping: {key}")
        mappings.append(PathMapping(source=Path(source), destination=Path(destination)))
    return mappings


def package_install_value(context: PackageContext, key: str) -> str:
    return required_string(context.settings.package_install, key)


def package_output_value(context: PackageContext, key: str) -> str:
    return required_string(context.settings.package_outputs, key)


def install_prefix(context: PackageContext) -> str:
    return settings_install_prefix(context.settings)


def install_home(context: PackageContext) -> str:
    return settings_install_home(context.settings)


def install_runtime_logs(context: PackageContext) -> str:
    return settings_install_runtime_logs(context.settings)


def install_app_bundle(context: PackageContext) -> str:
    return settings_install_app_bundle(context.settings)


def install_nginx_prefix(context: PackageContext) -> str:
    return settings_install_nginx_prefix(context.settings)


def install_nginx_bin(context: PackageContext) -> str:
    return f"{install_nginx_prefix(context)}/sbin/nginx"


def settings_install_value(settings: ReleaseSettings, key: str) -> str:
    return required_string(settings.package_install, key)


def settings_install_prefix(settings: ReleaseSettings) -> str:
    return settings_install_value(settings, "prefix")


def settings_install_home(settings: ReleaseSettings) -> str:
    return f"{settings_install_prefix(settings)}/vm"


def settings_install_runtime_logs(settings: ReleaseSettings) -> str:
    return f"{settings_install_prefix(settings)}/logs/runtime"


def settings_install_app_bundle(settings: ReleaseSettings) -> str:
    return (
        f"{settings_install_value(settings, 'applications_dir')}/"
        f"{settings.app_name}.app"
    )


def settings_install_nginx_prefix(settings: ReleaseSettings) -> str:
    return f"{settings_install_prefix(settings)}/nginx"


def package_path(context: PackageContext, path: str) -> Path:
    return context.pkg_root / path.strip("/")


def sync_release(root: Path, runtime_dir: Path, release_file: Path) -> None:
    run(
        [
            "python3",
            str(runtime_dir / "Support/Build/sync-release.py"),
            str(runtime_dir),
            str(release_file),
        ],
        cwd=root,
    )


def build_swift(
    runtime_dir: Path,
    sdkroot: str | None,
    clang_module_cache: str,
    helper_product_name: str,
) -> None:
    env = os.environ.copy()
    if sdkroot:
        env["SDKROOT"] = sdkroot
    env["CLANG_MODULE_CACHE_PATH"] = clang_module_cache
    run(["swift", "build", "-c", "release"], cwd=runtime_dir, env=env)
    run(
        ["swift", "build", "-c", "release", "--product", helper_product_name],
        cwd=runtime_dir,
        env=env,
    )


def sign_runtime_cli(runtime_cli: Path, runtime_dir: Path, identity: str) -> None:
    run(
        [
            "codesign",
            "--force",
            "--sign",
            identity,
            "--entitlements",
            str(runtime_dir / "Entitlements.shared.plist"),
            str(runtime_cli),
        ]
    )


def build_app_bundle(
    *,
    root: Path,
    runtime_dir: Path,
    helper_bin: Path,
    app_bundle: Path,
    app_name: str,
    helper_version: str,
    codesign_identity: str,
) -> None:
    if app_bundle.exists():
        shutil.rmtree(app_bundle)
    contents = app_bundle / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    shutil.copy2(helper_bin, macos / app_name)
    (macos / app_name).chmod(0o755)
    info_plist = contents / APP_INFO_PLIST_NAME
    shutil.copy2(runtime_dir / "Support/App" / APP_INFO_PLIST_NAME, info_plist)
    run(
        [
            "/usr/libexec/PlistBuddy",
            "-c",
            f"Set :CFBundleShortVersionString {helper_version}",
            str(info_plist),
        ]
    )
    shutil.copy2(runtime_dir / "Support/App" / APP_ICON_NAME, resources / APP_ICON_NAME)
    run(["codesign", "--force", "--sign", codesign_identity, str(app_bundle)], cwd=root)


def stage_update_artifacts(
    *,
    root: Path,
    runtime_dir: Path,
    settings: ReleaseSettings,
    artifact_dir: Path,
    app_bundle: Path,
    runtime_cli: Path,
    nginx_bundle: Path,
    docker_bundle: Path,
) -> StagedUpdateArtifacts:
    if artifact_dir.exists():
        shutil.rmtree(artifact_dir)
    runtime_tools_dir = artifact_dir / "runtime-tools"
    deploy_dir = artifact_dir / "deploy"
    runtime_tools_dir.mkdir(parents=True)
    deploy_dir.mkdir(parents=True)

    app_archive = artifact_dir / "app-bundle.tar.gz"
    tar_directory(app_archive, app_bundle.parent, app_bundle.name)

    packaging_dir = runtime_dir / "Support/Packaging"
    copy_executable(
        runtime_cli,
        runtime_tools_dir / Path(settings_install_value(settings, "bin")).name,
    )
    render_packaging_executable(
        settings,
        packaging_dir / "proxy-run.template",
        runtime_tools_dir / Path(settings_install_value(settings, "proxy_run")).name,
    )
    render_packaging_executable(
        settings,
        packaging_dir / "uninstall.template",
        runtime_tools_dir / Path(settings_install_value(settings, "uninstall")).name,
    )
    runtime_tools_archive = artifact_dir / "runtime-tools.tar.gz"
    tar_directory(
        runtime_tools_archive,
        runtime_tools_dir,
        Path(settings_install_value(settings, "bin")).name,
        Path(settings_install_value(settings, "proxy_run")).name,
        Path(settings_install_value(settings, "uninstall")).name,
    )

    nginx_dir = artifact_dir / "nginx"
    copy_tree(nginx_bundle, nginx_dir)
    nginx_archive = artifact_dir / "nginx-bundle.tar.gz"
    tar_directory(nginx_archive, artifact_dir, "nginx")

    stage_guest_deploy(root, runtime_dir, settings, deploy_dir, docker_bundle)
    guest_deploy_archive = artifact_dir / "guest-deploy.tar.gz"
    tar_directory(guest_deploy_archive, artifact_dir, "deploy")

    return StagedUpdateArtifacts(
        app_bundle=app_archive,
        runtime_tools=runtime_tools_archive,
        nginx_bundle=nginx_archive,
        guest_deploy=guest_deploy_archive,
    )


def stage_guest_deploy(
    root: Path,
    runtime_dir: Path,
    settings: ReleaseSettings,
    deploy_dir: Path,
    docker_bundle: Path,
) -> None:
    copy_tree(runtime_dir / "Support/Guest", deploy_dir, merge=True)
    for entry in required_path_mappings(settings.guest_deploy, "paths"):
        copy_tree(root / entry.source, deploy_dir / entry.destination)
    for entry in required_path_mappings(settings.guest_deploy, "files"):
        install_file(root / entry.source, deploy_dir / entry.destination)
    install_file(
        docker_bundle,
        deploy_dir
        / required_string(settings.guest_deploy, "docker_image_bundle_destination"),
    )


def tar_directory(archive_path: Path, base_dir: Path, *names: str) -> None:
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w:gz") as archive:
        for name in names:
            archive.add(base_dir / name, arcname=name)


def copy_executable(source: Path, destination: Path) -> None:
    install_file(source, destination)
    destination.chmod(0o755)


def render_packaging_executable(
    settings: ReleaseSettings,
    template: Path,
    destination: Path,
) -> None:
    render_packaging_template(settings, template, destination)
    destination.chmod(0o755)


def render_packaging_template(
    settings: ReleaseSettings,
    template: Path,
    destination: Path,
    extra_values: dict[str, str] | None = None,
) -> None:
    values = packaging_template_values(settings)
    if extra_values:
        values.update(extra_values)
    render_template(template, destination, values)


def packaging_template_values(settings: ReleaseSettings) -> dict[str, str]:
    return {
        "PRODUCT_ROOT": shell_double_quoted_content(settings_install_prefix(settings)),
        "VM_HOME": shell_double_quoted_content(settings_install_home(settings)),
        "INSTALL_LOG": shell_double_quoted_content(
            f"{settings_install_prefix(settings)}/logs/install.log"
        ),
        "VM_BIN": shell_double_quoted_content(settings_install_value(settings, "bin")),
        "PROXY_RUN": shell_double_quoted_content(
            settings_install_value(settings, "proxy_run")
        ),
        "UNINSTALL": shell_double_quoted_content(
            settings_install_value(settings, "uninstall")
        ),
        "MANAGER_APP": shell_double_quoted_content(
            settings_install_app_bundle(settings)
        ),
        "NGINX_PREFIX": shell_double_quoted_content(
            settings_install_nginx_prefix(settings)
        ),
        "LAUNCH_DAEMONS_DIR": shell_double_quoted_content(settings_install_value(
            settings,
            "launch_daemons_dir",
        )),
        "UNINSTALL_LOG": shell_double_quoted_content(
            settings_install_value(settings, "uninstall_log")
        ),
        "PRESERVE_TMP_TEMPLATE": shell_double_quoted_content(settings_install_value(
            settings,
            "preserve_tmp_template",
        )),
        "PACKAGE_IDENTIFIER": shell_double_quoted_content(
            required_string(settings.package, "identifier")
        ),
    }


def shell_double_quoted_content(value: str) -> str:
    return (
        value
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("$", "\\$")
        .replace("`", "\\`")
        .replace("\n", "\\n")
    )


def plist_text(value: str) -> str:
    return xml_escape(value)


def install_file(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise SystemExit(f"error: missing file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def copy_tree(source: Path, destination: Path, *, merge: bool = False) -> None:
    if not source.is_dir():
        raise SystemExit(f"error: missing directory: {source}")
    if destination.exists() and not merge:
        shutil.rmtree(destination)
    shutil.copytree(
        source,
        destination,
        dirs_exist_ok=merge,
        ignore=shutil.ignore_patterns(".DS_Store", "._*", "__pycache__"),
    )


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
            required_string(context.settings.package, "identifier"),
            "--version",
            str(context.release["helperVersion"]),
            "--install-location",
            "/",
            str(context.pkg_output),
        ],
        env={**os.environ, "COPYFILE_DISABLE": "1"},
    )


def build_dmg(context: PackageContext) -> None:
    staging = context.settings.dmg_staging_dir
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    install_file(
        context.pkg_output,
        staging / package_output_value(context, "dmg_pkg_name"),
    )
    context.dmg_output.parent.mkdir(parents=True, exist_ok=True)
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


def stage_pkg_root(context: PackageContext) -> None:
    image = context.golden_runtime_dir / "Image"
    initrd = context.golden_runtime_dir / "initrd.img"
    for required in [image, initrd, context.rootfs_base, context.docker_bundle]:
        if not required.is_file():
            raise SystemExit(f"error: missing package input: {required}")

    if context.pkg_root.exists():
        shutil.rmtree(context.pkg_root)
    if context.pkg_scripts.exists():
        shutil.rmtree(context.pkg_scripts)

    mkdirs = [
        package_path(context, package_install_value(context, "applications_dir")),
        package_path(
            context,
            Path(package_install_value(context, "bin")).parent.as_posix(),
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
        package_path(context, package_install_value(context, "bin")),
    )
    run(
        [
            "codesign",
            "--force",
            "--sign",
            "-",
            "--entitlements",
            str(context.runtime_dir / "Entitlements.shared.plist"),
            str(package_path(context, package_install_value(context, "bin"))),
        ]
    )
    assert_virtualization_entitlement(
        package_path(context, package_install_value(context, "bin"))
    )

    packaging_dir = context.runtime_dir / "Support/Packaging"
    render_packaging_executable(
        context.settings,
        packaging_dir / "proxy-run.template",
        package_path(context, package_install_value(context, "proxy_run")),
    )
    render_packaging_executable(
        context.settings,
        packaging_dir / "uninstall.template",
        package_path(context, package_install_value(context, "uninstall")),
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
        context.root / "infra/macos-nginx/vitalserver.conf.template",
        package_path(
            context,
            f"{install_home(context)}/Support/Proxy/vitalserver.conf.template",
        ),
    )
    stage_guest_deploy(
        context.root,
        context.runtime_dir,
        context.settings,
        package_path(context, f"{install_home(context)}/data/deploy"),
        context.docker_bundle,
    )
    render_launchd_templates(context)
    copy_executable(packaging_dir / "preinstall", context.pkg_scripts / "preinstall")
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


def render_launchd_templates(context: PackageContext) -> None:
    launchd = context.runtime_dir / "launchd"
    daemon_dir = package_path(
        context,
        package_install_value(context, "launch_daemons_dir"),
    )
    templates = context.settings.launchd
    vm_template = section(templates, "vm")
    proxy_template = section(templates, "proxy")
    watchdog_template = section(templates, "watchdog")
    render_template(
        launchd / required_string(vm_template, "template"),
        daemon_dir / required_string(vm_template, "output"),
        {
            "VITALSERVER_VM_BIN": package_install_value(context, "bin"),
            "VITALSERVER_VM_HOME": install_home(context),
            "VITALSERVER_RUNTIME_LOGS": install_runtime_logs(context),
        },
    )
    render_template(
        launchd / required_string(proxy_template, "template"),
        daemon_dir / required_string(proxy_template, "output"),
        {
            "VITALSERVER_PROXY_RUN": package_install_value(context, "proxy_run"),
            "VITALSERVER_VM_HOME": install_home(context),
            "VITALSERVER_RUNTIME_LOGS": install_runtime_logs(context),
            "VITALSERVER_NGINX_PREFIX": install_nginx_prefix(context),
            "VITALSERVER_NGINX_BIN": install_nginx_bin(context),
            "VITALSERVER_PROXY_PORT": context.proxy_port,
        },
    )
    render_template(
        launchd / required_string(watchdog_template, "template"),
        daemon_dir / required_string(watchdog_template, "output"),
        {
            "VITALSERVER_VM_BIN": package_install_value(context, "bin"),
            "VITALSERVER_VM_HOME": install_home(context),
            "VITALSERVER_RUNTIME_LOGS": install_runtime_logs(context),
        },
    )


def render_template(template: Path, output: Path, values: dict[str, str]) -> None:
    run_render_template(
        Namespace(
            template=template,
            output=output,
            var=[f"{key}={value}" for key, value in values.items()],
        )
    )


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


def remove_apple_double_files(path: Path) -> None:
    for child in path.rglob("._*"):
        if child.is_file():
            child.unlink()
