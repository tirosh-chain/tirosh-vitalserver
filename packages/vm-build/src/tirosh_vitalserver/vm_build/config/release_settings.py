from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.vm_build.config.build_config import (
    load_config,
    required_string,
    section,
)
from tirosh_vitalserver.vm_build.config.guest_deploy import (
    GuestDeployConfig,
    load_guest_deploy_config,
)

RUNTIME_CLI_NAME = "vitalserver-vm"


@dataclass(frozen=True)
class PackageInstallConfig:
    prefix: str
    applications_dir: str
    launch_daemons_dir: str
    bin: str
    proxy_run: str
    uninstall: str
    settings_path: str
    uninstall_log: str
    preserve_tmp_template: str


@dataclass(frozen=True)
class PackageOutputConfig:
    pkg_name_template: str
    dmg_name_template: str
    dmg_pkg_name: str
    dmg_staging_dir: Path


@dataclass(frozen=True)
class LaunchdTemplateConfig:
    template: str
    output: str


@dataclass(frozen=True)
class LaunchdConfig:
    vm: LaunchdTemplateConfig
    proxy: LaunchdTemplateConfig
    watchdog: LaunchdTemplateConfig


@dataclass(frozen=True)
class ReleaseBuildSettings:
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
    pkg_root: Path
    pkg_scripts: Path
    pkg_component_plist: Path
    dmg_staging_dir: Path
    dist_dir: Path
    package_identifier: str
    install: PackageInstallConfig
    outputs: PackageOutputConfig
    guest_deploy: GuestDeployConfig
    launchd: LaunchdConfig


def resolve_path(root: Path, value: str | Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def load_release_build_settings(
    config_path: Path,
    root: Path,
) -> ReleaseBuildSettings:
    config = load_config(config_path)
    workspace = section(config, "workspace")
    app = section(config, "app")
    package = section(config, "package")
    package_install = section(package, "install")
    package_outputs = section(package, "outputs")
    outputs = load_package_outputs(package_outputs, root)
    runtime_dir = resolve_path(root, required_string(workspace, "runtime_dir"))
    build_dir = resolve_path(root, required_string(workspace, "build_dir"))
    app_name = required_string(app, "name")
    helper_product_name = required_string(app, "helper_product_name")
    return ReleaseBuildSettings(
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
        pkg_root=build_dir / "root",
        pkg_scripts=build_dir / "scripts",
        pkg_component_plist=build_dir / "components.plist",
        dmg_staging_dir=outputs.dmg_staging_dir,
        dist_dir=resolve_path(root, required_string(workspace, "dist_dir")),
        package_identifier=required_string(package, "identifier"),
        install=load_package_install(package_install),
        outputs=outputs,
        guest_deploy=load_guest_deploy_config(section(config, "guest_deploy")),
        launchd=load_launchd_config(section(config, "launchd")),
    )


def load_package_install(config: dict[str, object]) -> PackageInstallConfig:
    return PackageInstallConfig(
        prefix=required_string(config, "prefix"),
        applications_dir=required_string(config, "applications_dir"),
        launch_daemons_dir=required_string(config, "launch_daemons_dir"),
        bin=required_string(config, "bin"),
        proxy_run=required_string(config, "proxy_run"),
        uninstall=required_string(config, "uninstall"),
        settings_path=required_string(config, "settings_path"),
        uninstall_log=required_string(config, "uninstall_log"),
        preserve_tmp_template=required_string(config, "preserve_tmp_template"),
    )


def load_package_outputs(
    config: dict[str, object],
    root: Path,
) -> PackageOutputConfig:
    return PackageOutputConfig(
        pkg_name_template=required_string(config, "pkg_name_template"),
        dmg_name_template=required_string(config, "dmg_name_template"),
        dmg_pkg_name=required_string(config, "dmg_pkg_name"),
        dmg_staging_dir=resolve_path(root, required_string(config, "dmg_staging_dir")),
    )


def load_launchd_config(config: dict[str, object]) -> LaunchdConfig:
    return LaunchdConfig(
        vm=load_launchd_template(section(config, "vm")),
        proxy=load_launchd_template(section(config, "proxy")),
        watchdog=load_launchd_template(section(config, "watchdog")),
    )


def load_launchd_template(config: dict[str, object]) -> LaunchdTemplateConfig:
    return LaunchdTemplateConfig(
        template=required_string(config, "template"),
        output=required_string(config, "output"),
    )


def settings_install_value(settings: ReleaseBuildSettings, key: str) -> str:
    value = getattr(settings.install, key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing package install config value: {key}")
    return value


def settings_install_prefix(settings: ReleaseBuildSettings) -> str:
    return settings_install_value(settings, "prefix")


def settings_install_home(settings: ReleaseBuildSettings) -> str:
    return f"{settings_install_prefix(settings)}/vm"


def settings_install_runtime_logs(settings: ReleaseBuildSettings) -> str:
    return f"{settings_install_prefix(settings)}/logs/runtime"


def settings_install_app_bundle(settings: ReleaseBuildSettings) -> str:
    return (
        f"{settings_install_value(settings, 'applications_dir')}/"
        f"{settings.app_name}.app"
    )


def settings_install_nginx_prefix(settings: ReleaseBuildSettings) -> str:
    return f"{settings_install_prefix(settings)}/nginx"
