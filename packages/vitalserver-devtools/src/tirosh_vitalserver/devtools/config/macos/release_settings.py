from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    TomlTable,
    load_build_toml,
    nested_section,
    required_string,
    section,
)
from tirosh_vitalserver.devtools.config.docker_images import load_docker_images_config
from tirosh_vitalserver.devtools.config.guest_deploy import (
    load_guest_deploy_config,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.core.macos_release.settings import (
    MacOSInstallConfig,
    MacOSLaunchdConfig,
    MacOSLaunchdTemplateConfig,
    MacOSPackageOutputConfig,
    MacOSReleaseSettings,
)


def load_macos_release_settings(
    config_path: Path,
    root: Path,
) -> MacOSReleaseSettings:
    config = load_build_toml(config_path)
    workspace = section(config, "workspace")
    macos = section(config, "macos")
    app = section(macos, "app", path="macos")
    package = section(macos, "package", path="macos")
    package_install = section(macos, "install", path="macos")
    package_outputs = section(package, "outputs", path="macos.package")
    outputs = load_macos_package_outputs(package_outputs, root)
    docker_images = load_docker_images_config(config, root)
    runtime_dir = resolve_path(
        root,
        required_string(workspace, "macos_runtime_source_dir", path="workspace"),
    )
    build_dir = resolve_path(
        root,
        required_string(workspace, "build_dir", path="workspace"),
    )
    app_name = required_string(app, "name", path="macos.app")
    helper_product_name = required_string(
        app,
        "helper_product_name",
        path="macos.app",
    )
    runtime_cli_product_name = required_string(
        app,
        "runtime_cli_product_name",
        path="macos.app",
    )
    return MacOSReleaseSettings(
        runtime_dir=runtime_dir,
        helper_product_name=helper_product_name,
        app_name=app_name,
        app_bundle=resolve_path(
            root,
            required_string(app, "bundle_dir", path="macos.app"),
        ),
        clang_module_cache=resolve_path(
            root,
            required_string(workspace, "clang_module_cache", path="workspace"),
        ),
        runtime_cli=runtime_dir / ".build/release" / runtime_cli_product_name,
        helper_bin=runtime_dir / ".build/release" / helper_product_name,
        nginx_bundle=build_dir / "nginx-bundle",
        docker_bundle=docker_images.bundle_path,
        update_artifact_dir=build_dir / "update-artifacts",
        pkg_root=build_dir / "root",
        pkg_scripts=build_dir / "scripts",
        pkg_component_plist=build_dir / "components.plist",
        dmg_staging_dir=outputs.dmg_staging_dir,
        dist_dir=resolve_path(
            root,
            required_string(workspace, "dist_dir", path="workspace"),
        ),
        package_identifier=required_string(package, "identifier", path="macos.package"),
        install=load_macos_install(package_install),
        outputs=outputs,
        guest_deploy=load_guest_deploy_config(config),
        launchd=load_macos_launchd(section(macos, "launchd", path="macos")),
    )


def load_macos_install(config: TomlTable) -> MacOSInstallConfig:
    return MacOSInstallConfig(
        product_root=required_string(config, "product_root", path="macos.install"),
        applications_dir=required_string(
            config,
            "applications_dir",
            path="macos.install",
        ),
        launch_daemons_dir=required_string(
            config,
            "launch_daemons_dir",
            path="macos.install",
        ),
        vm_cli=required_string(config, "vm_cli", path="macos.install"),
        proxy_runner=required_string(config, "proxy_runner", path="macos.install"),
        uninstaller=required_string(config, "uninstaller", path="macos.install"),
        install_settings_json=required_string(
            config,
            "install_settings_json",
            path="macos.install",
        ),
        uninstall_log=required_string(config, "uninstall_log", path="macos.install"),
        preserve_tmp_template=required_string(
            config,
            "preserve_tmp_template",
            path="macos.install",
        ),
    )


def load_macos_package_outputs(
    config: TomlTable,
    root: Path,
) -> MacOSPackageOutputConfig:
    return MacOSPackageOutputConfig(
        pkg_filename_template=required_string(
            config,
            "pkg_filename_template",
            path="macos.package.outputs",
        ),
        dmg_filename_template=required_string(
            config,
            "dmg_filename_template",
            path="macos.package.outputs",
        ),
        dmg_installer_pkg_name=required_string(
            config,
            "dmg_installer_pkg_name",
            path="macos.package.outputs",
        ),
        dmg_staging_dir=resolve_path(
            root,
            required_string(config, "dmg_staging_dir", path="macos.package.outputs"),
        ),
    )


def load_macos_launchd(config: TomlTable) -> MacOSLaunchdConfig:
    return MacOSLaunchdConfig(
        platform_agent=load_macos_launchd_template(
            nested_section(config, "platform_agent", parent_path="macos.launchd"),
            path="macos.launchd.platform_agent",
        ),
        vm=load_macos_launchd_template(
            nested_section(config, "vm", parent_path="macos.launchd"),
            path="macos.launchd.vm",
        ),
        proxy=load_macos_launchd_template(
            nested_section(config, "proxy", parent_path="macos.launchd"),
            path="macos.launchd.proxy",
        ),
        guest_log_sync=load_macos_launchd_template(
            nested_section(config, "guest_log_sync", parent_path="macos.launchd"),
            path="macos.launchd.guest_log_sync",
        ),
        sleep_prevention=load_macos_launchd_template(
            nested_section(config, "sleep_prevention", parent_path="macos.launchd"),
            path="macos.launchd.sleep_prevention",
        ),
        watchdog=load_macos_launchd_template(
            nested_section(config, "watchdog", parent_path="macos.launchd"),
            path="macos.launchd.watchdog",
        ),
        automatic_backup=load_macos_launchd_template(
            nested_section(config, "automatic_backup", parent_path="macos.launchd"),
            path="macos.launchd.automatic_backup",
        ),
    )


def load_macos_launchd_template(
    config: TomlTable,
    *,
    path: str,
) -> MacOSLaunchdTemplateConfig:
    return MacOSLaunchdTemplateConfig(
        template_file=required_string(config, "template_file", path=path),
        installed_plist=required_string(config, "installed_plist", path=path),
    )


__all__ = [
    "MacOSInstallConfig",
    "MacOSLaunchdConfig",
    "MacOSLaunchdTemplateConfig",
    "MacOSPackageOutputConfig",
    "MacOSReleaseSettings",
    "load_macos_release_settings",
]
