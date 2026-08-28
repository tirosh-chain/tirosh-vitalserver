from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.settings import MacOSReleaseSettings


def settings_install_value(settings: MacOSReleaseSettings, key: str) -> str:
    value = getattr(settings.install, key)
    if not isinstance(value, str) or not value:
        raise DomainError(f"error: missing package install config value: {key}")
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


def settings_host_platform_installation_root(
    settings: MacOSReleaseSettings,
) -> str:
    return f"{settings_install_prefix(settings)}/host-platform"


def settings_host_platform_current_release(
    settings: MacOSReleaseSettings,
) -> str:
    return f"{settings_host_platform_installation_root(settings)}/current"


def settings_host_platform_release_slot(
    settings: MacOSReleaseSettings,
    release_id: str,
) -> str:
    return f"{settings_host_platform_installation_root(settings)}/releases/{release_id}"


def settings_current_release_app_bundle(settings: MacOSReleaseSettings) -> str:
    return (
        f"{settings_host_platform_current_release(settings)}/"
        f"app/{settings.app_name}.app"
    )


def settings_current_release_binary(
    settings: MacOSReleaseSettings,
    name: str,
) -> str:
    return f"{settings_host_platform_current_release(settings)}/bin/{name}"


def settings_current_release_nginx_prefix(settings: MacOSReleaseSettings) -> str:
    return f"{settings_host_platform_current_release(settings)}/nginx"


def settings_install_platform_agent(settings: MacOSReleaseSettings) -> str:
    return (
        f"{settings_current_release_app_bundle(settings)}/Contents/MacOS/"
        "vitalserver-platform-agent"
    )


def settings_install_update_handoff_jobs(
    settings: MacOSReleaseSettings,
) -> str:
    return f"{settings_install_prefix(settings)}/update-handoff/jobs"


def settings_install_nginx_prefix(settings: MacOSReleaseSettings) -> str:
    return f"{settings_install_prefix(settings)}/nginx"


def package_install_value(context: PackageContext, key: str) -> str:
    return settings_install_value(context.settings, key)


def package_output_value(context: PackageContext, key: str) -> str:
    value = getattr(context.settings.outputs, key)
    if not isinstance(value, str) or not value:
        raise DomainError(f"error: missing package output config value: {key}")
    return value


def install_prefix(context: PackageContext) -> str:
    return settings_install_prefix(context.settings)


def install_home(context: PackageContext) -> str:
    return settings_install_home(context.settings)


def install_runtime_logs(context: PackageContext) -> str:
    return settings_install_runtime_logs(context.settings)


def install_app_bundle(context: PackageContext) -> str:
    return settings_install_app_bundle(context.settings)


def install_platform_agent(context: PackageContext) -> str:
    return settings_install_platform_agent(context.settings)


def install_update_handoff_jobs(context: PackageContext) -> str:
    return settings_install_update_handoff_jobs(context.settings)


def install_nginx_prefix(context: PackageContext) -> str:
    return settings_install_nginx_prefix(context.settings)


def install_nginx_bin(context: PackageContext) -> str:
    return f"{settings_current_release_nginx_prefix(context.settings)}/sbin/nginx"


def package_path(context: PackageContext, path: str) -> Path:
    return context.pkg_root / path.strip("/")
