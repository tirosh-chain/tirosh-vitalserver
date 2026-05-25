from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    load_build_toml,
    required_string,
    section,
)
from tirosh_vitalserver.devtools.config.guest_deploy import (
    GuestDeployConfig,
    load_guest_deploy_config,
)

RUNTIME_CLI_NAME = "vitalserver-vm"


@dataclass(frozen=True)
class MacOSInstallConfig:
    product_root: str
    applications_dir: str
    launch_daemons_dir: str
    vm_cli: str
    proxy_runner: str
    uninstaller: str
    install_settings_json: str
    uninstall_log: str
    preserve_tmp_template: str


@dataclass(frozen=True)
class MacOSPackageOutputConfig:
    pkg_filename_template: str
    dmg_filename_template: str
    dmg_installer_pkg_name: str
    dmg_staging_dir: Path


@dataclass(frozen=True)
class MacOSLaunchdTemplateConfig:
    template_file: str
    installed_plist: str


@dataclass(frozen=True)
class MacOSLaunchdConfig:
    vm: MacOSLaunchdTemplateConfig
    proxy: MacOSLaunchdTemplateConfig
    watchdog: MacOSLaunchdTemplateConfig


@dataclass(frozen=True)
class MacOSReleaseSettings:
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
    install: MacOSInstallConfig
    outputs: MacOSPackageOutputConfig
    guest_deploy: GuestDeployConfig
    launchd: MacOSLaunchdConfig


def resolve_path(root: Path, value: str | Path) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else root / path


def load_macos_release_settings(
    config_path: Path,
    root: Path,
) -> MacOSReleaseSettings:
    config = load_build_toml(config_path)
    workspace = section(config, "workspace")
    macos = section(config, "macos")
    app = section(macos, "app")
    package = section(macos, "package")
    package_install = section(macos, "install")
    package_outputs = section(package, "outputs")
    outputs = load_macos_package_outputs(package_outputs, root)
    runtime_dir = resolve_path(root, required_string(workspace, "runtime_dir"))
    build_dir = resolve_path(root, required_string(workspace, "build_dir"))
    app_name = required_string(app, "name")
    helper_product_name = required_string(app, "helper_product_name")
    return MacOSReleaseSettings(
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
        install=load_macos_install(package_install),
        outputs=outputs,
        guest_deploy=load_guest_deploy_config(section(config, "guest_deploy")),
        launchd=load_macos_launchd(section(macos, "launchd")),
    )


def load_macos_install(config: dict[str, object]) -> MacOSInstallConfig:
    return MacOSInstallConfig(
        product_root=required_string(config, "product_root"),
        applications_dir=required_string(config, "applications_dir"),
        launch_daemons_dir=required_string(config, "launch_daemons_dir"),
        vm_cli=required_string(config, "vm_cli"),
        proxy_runner=required_string(config, "proxy_runner"),
        uninstaller=required_string(config, "uninstaller"),
        install_settings_json=required_string(config, "install_settings_json"),
        uninstall_log=required_string(config, "uninstall_log"),
        preserve_tmp_template=required_string(config, "preserve_tmp_template"),
    )


def load_macos_package_outputs(
    config: dict[str, object],
    root: Path,
) -> MacOSPackageOutputConfig:
    return MacOSPackageOutputConfig(
        pkg_filename_template=required_string(config, "pkg_filename_template"),
        dmg_filename_template=required_string(config, "dmg_filename_template"),
        dmg_installer_pkg_name=required_string(config, "dmg_installer_pkg_name"),
        dmg_staging_dir=resolve_path(root, required_string(config, "dmg_staging_dir")),
    )


def load_macos_launchd(config: dict[str, object]) -> MacOSLaunchdConfig:
    return MacOSLaunchdConfig(
        vm=load_macos_launchd_template(section(config, "vm")),
        proxy=load_macos_launchd_template(section(config, "proxy")),
        watchdog=load_macos_launchd_template(section(config, "watchdog")),
    )


def load_macos_launchd_template(
    config: dict[str, object],
) -> MacOSLaunchdTemplateConfig:
    return MacOSLaunchdTemplateConfig(
        template_file=required_string(config, "template_file"),
        installed_plist=required_string(config, "installed_plist"),
    )


def settings_install_value(settings: MacOSReleaseSettings, key: str) -> str:
    value = getattr(settings.install, key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing package install config value: {key}")
    return value


def settings_install_prefix(settings: MacOSReleaseSettings) -> str:
    return settings_install_value(settings, "product_root")


def settings_install_home(settings: MacOSReleaseSettings) -> str:
    return f"{settings_install_prefix(settings)}/vm"


def settings_install_runtime_logs(settings: MacOSReleaseSettings) -> str:
    return f"{settings_install_prefix(settings)}/logs/runtime"


def settings_install_app_bundle(settings: MacOSReleaseSettings) -> str:
    return (
        f"{settings_install_value(settings, 'applications_dir')}/"
        f"{settings.app_name}.app"
    )


def settings_install_nginx_prefix(settings: MacOSReleaseSettings) -> str:
    return f"{settings_install_prefix(settings)}/nginx"
