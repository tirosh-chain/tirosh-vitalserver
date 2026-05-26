from __future__ import annotations

from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

from tirosh_vitalserver.devtools.adapters.toolchain.token_template import (
    run_render_template,
)
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    install_home,
    install_nginx_bin,
    install_nginx_prefix,
    install_runtime_logs,
    package_install_value,
    package_path,
    settings_install_app_bundle,
    settings_install_home,
    settings_install_nginx_prefix,
    settings_install_prefix,
    settings_install_value,
)
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.settings import (
    MacOSReleaseSettings,
)


def render_packaging_executable(
    settings: MacOSReleaseSettings,
    template: Path,
    destination: Path,
) -> None:
    render_packaging_template(settings, template, destination)
    destination.chmod(0o755)


def render_packaging_template(
    settings: MacOSReleaseSettings,
    template: Path,
    destination: Path,
    extra_values: dict[str, str] | None = None,
) -> None:
    values = packaging_template_values(settings)
    if extra_values:
        values.update(extra_values)
    render_template(template, destination, values)


def packaging_template_values(settings: MacOSReleaseSettings) -> dict[str, str]:
    return {
        "PRODUCT_ROOT": shell_double_quoted_content(settings_install_prefix(settings)),
        "VM_HOME": shell_double_quoted_content(settings_install_home(settings)),
        "INSTALL_LOG": shell_double_quoted_content(
            f"{settings_install_prefix(settings)}/logs/install.log"
        ),
        "VM_BIN": shell_double_quoted_content(
            settings_install_value(settings, "vm_cli")
        ),
        "PROXY_RUN": shell_double_quoted_content(
            settings_install_value(settings, "proxy_runner")
        ),
        "UNINSTALL": shell_double_quoted_content(
            settings_install_value(settings, "uninstaller")
        ),
        "MANAGER_APP": shell_double_quoted_content(
            settings_install_app_bundle(settings)
        ),
        "NGINX_PREFIX": shell_double_quoted_content(
            settings_install_nginx_prefix(settings)
        ),
        "LAUNCH_DAEMONS_DIR": shell_double_quoted_content(
            settings_install_value(
                settings,
                "launch_daemons_dir",
            )
        ),
        "UNINSTALL_LOG": shell_double_quoted_content(
            settings_install_value(settings, "uninstall_log")
        ),
        "PRESERVE_TMP_TEMPLATE": shell_double_quoted_content(
            settings_install_value(
                settings,
                "preserve_tmp_template",
            )
        ),
        "PACKAGE_IDENTIFIER": shell_double_quoted_content(settings.package_identifier),
    }


def shell_double_quoted_content(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("$", "\\$")
        .replace("`", "\\`")
        .replace("\n", "\\n")
    )


def plist_text(value: str) -> str:
    return xml_escape(value)


def render_launchd_templates(context: PackageContext) -> None:
    launchd = context.runtime_dir / "launchd"
    daemon_dir = package_path(
        context,
        package_install_value(context, "launch_daemons_dir"),
    )
    templates = context.settings.launchd
    render_template(
        launchd / templates.vm.template_file,
        daemon_dir / templates.vm.installed_plist,
        {
            "VITALSERVER_VM_BIN": package_install_value(context, "vm_cli"),
            "VITALSERVER_VM_HOME": install_home(context),
            "VITALSERVER_RUNTIME_LOGS": install_runtime_logs(context),
        },
    )
    render_template(
        launchd / templates.proxy.template_file,
        daemon_dir / templates.proxy.installed_plist,
        {
            "VITALSERVER_PROXY_RUN": package_install_value(context, "proxy_runner"),
            "VITALSERVER_VM_HOME": install_home(context),
            "VITALSERVER_RUNTIME_LOGS": install_runtime_logs(context),
            "VITALSERVER_NGINX_PREFIX": install_nginx_prefix(context),
            "VITALSERVER_NGINX_BIN": install_nginx_bin(context),
            "VITALSERVER_PROXY_PORT": context.proxy_port,
        },
    )
    render_template(
        launchd / templates.guest_log_sync.template_file,
        daemon_dir / templates.guest_log_sync.installed_plist,
        {
            "VITALSERVER_VM_BIN": package_install_value(context, "vm_cli"),
            "VITALSERVER_VM_HOME": install_home(context),
            "VITALSERVER_RUNTIME_LOGS": install_runtime_logs(context),
        },
    )
    render_template(
        launchd / templates.watchdog.template_file,
        daemon_dir / templates.watchdog.installed_plist,
        {
            "VITALSERVER_VM_BIN": package_install_value(context, "vm_cli"),
            "VITALSERVER_VM_HOME": install_home(context),
            "VITALSERVER_RUNTIME_LOGS": install_runtime_logs(context),
        },
    )


def render_template(template: Path, output: Path, values: dict[str, str]) -> None:
    run_render_template(
        template,
        output,
        [f"{key}={value}" for key, value in values.items()],
    )
