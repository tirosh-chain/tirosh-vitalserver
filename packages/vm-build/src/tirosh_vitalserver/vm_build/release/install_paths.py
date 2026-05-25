from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.vm_build.config.release_settings import (
    settings_install_app_bundle,
    settings_install_home,
    settings_install_nginx_prefix,
    settings_install_prefix,
    settings_install_runtime_logs,
)
from tirosh_vitalserver.vm_build.release.models import PackageContext


def package_install_value(context: PackageContext, key: str) -> str:
    value = getattr(context.settings.install, key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing package install config value: {key}")
    return value


def package_output_value(context: PackageContext, key: str) -> str:
    value = getattr(context.settings.outputs, key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing package output config value: {key}")
    return value


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


def package_path(context: PackageContext, path: str) -> Path:
    return context.pkg_root / path.strip("/")
