from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.guest_deploy import GuestDeployConfig


@dataclass(frozen=True)
class MacOSInstallConfig:
    product_root: str
    applications_dir: str
    launch_daemons_dir: str
    vm_cli: str
    update_handoff_supervisor: str
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
    platform_agent: MacOSLaunchdTemplateConfig
    update_handoff_supervisor: MacOSLaunchdTemplateConfig
    vm: MacOSLaunchdTemplateConfig
    proxy: MacOSLaunchdTemplateConfig
    guest_log_sync: MacOSLaunchdTemplateConfig
    sleep_prevention: MacOSLaunchdTemplateConfig
    watchdog: MacOSLaunchdTemplateConfig
    automatic_backup: MacOSLaunchdTemplateConfig


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
