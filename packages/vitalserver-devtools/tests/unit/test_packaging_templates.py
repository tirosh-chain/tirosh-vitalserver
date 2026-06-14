from __future__ import annotations

import os
import signal
import subprocess
import time
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.macos_release.installer_templates import (
    render_packaging_executable,
    render_packaging_template,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    settings_install_app_bundle,
)


def test_packaging_templates_render_from_build_config(tmp_path: Path) -> None:
    root = repo_root()
    settings = load_macos_release_settings(
        root / "config/vm-build.toml",
        root,
    )
    packaging = root / "apps/vitalserver-macos-runtime/Support/Packaging"
    proxy_config_template = root / "infra/macos-nginx/vitalserver.conf.template"
    installer_package_source = (
        root
        / "packages/vitalserver-devtools/src/tirosh_vitalserver/devtools"
        / "adapters/macos_release/installer_package.py"
    )

    postinstall = tmp_path / "postinstall"
    proxy_run = tmp_path / "vitalserver-proxy-run"
    uninstall = tmp_path / "tirosh-vitalserver-uninstall"
    reset_for_reinstall_command = tmp_path / "reset-for-reinstall.command"
    upstream_redis_backup_command = tmp_path / "upstream-redis-backup.command"
    components = tmp_path / "components.plist"

    render_packaging_executable(
        settings,
        packaging / "postinstall.template",
        postinstall,
    )
    render_packaging_executable(
        settings,
        packaging / "proxy-run.template",
        proxy_run,
    )
    render_packaging_executable(
        settings,
        packaging / "uninstall.template",
        uninstall,
    )
    render_packaging_executable(
        settings,
        packaging / "reset-for-reinstall-command.template",
        reset_for_reinstall_command,
    )
    render_packaging_executable(
        settings,
        packaging / "upstream-redis-backup-command.template",
        upstream_redis_backup_command,
    )
    render_packaging_template(
        settings,
        packaging / "components.plist.template",
        components,
        {
            "APP_BUNDLE_ROOT_RELATIVE": settings_install_app_bundle(settings).strip(
                "/"
            ),
        },
    )

    rendered = "\n".join(
        path.read_text(encoding="utf-8")
        for path in [
            postinstall,
            proxy_run,
            uninstall,
            reset_for_reinstall_command,
            upstream_redis_backup_command,
            components,
        ]
    )
    preinstall_text = (packaging / "preinstall").read_text(encoding="utf-8")
    uninstall_text = uninstall.read_text(encoding="utf-8")
    reset_for_reinstall_command_text = reset_for_reinstall_command.read_text(
        encoding="utf-8"
    )
    upstream_redis_backup_command_text = upstream_redis_backup_command.read_text(
        encoding="utf-8"
    )
    postinstall_text = postinstall.read_text(encoding="utf-8")
    proxy_run_text = proxy_run.read_text(encoding="utf-8")
    assert "${PRODUCT_ROOT}" not in rendered
    assert "${NGINX_PREFIX}" not in rendered
    assert "pkg install supports fresh installs only" in preinstall_text
    assert 'preflight_bin="${script_dir}/vitalserver-vm-preinstall"' in preinstall_text
    assert '"${preflight_bin}" runtime preinstall-check' in preinstall_text
    assert (
        'context.pkg_scripts / "vitalserver-vm-preinstall"'
        in installer_package_source.read_text(encoding="utf-8")
    )
    assert "pkgutil --pkg-info" not in preinstall_text
    assert "launchctl print" not in preinstall_text
    assert "lsof -nP" not in preinstall_text
    assert "plutil -extract" not in preinstall_text
    assert "/Library/Application Support/VitalServerHelper" in rendered
    assert '"${vm_bin}" runtime install-provision' in postinstall_text
    assert "postinstall_timeout_seconds" not in postinstall_text
    assert "runtime install timed out timeoutSeconds=" not in postinstall_text
    assert "postinstall failure cleanup started" in postinstall_text
    assert "tirosh-vitalserver-postinstall-failure.log" in postinstall_text
    assert (
        'vm_home="/Library/Application Support/VitalServerHelper/vm"'
        in postinstall_text
    )
    assert 'manager_app="/Applications/VitalServer Helper.app"' in postinstall_text
    assert '"${manager_app}"' in postinstall_text
    assert '"${vm_bin}"' in postinstall_text
    assert "VitalServer Helper postinstall started" in postinstall_text
    assert "VitalServer Helper postinstall completed" in postinstall_text
    assert 'launchctl bootout "system/${label}"' in postinstall_text
    assert "ai.tirosh.vitalserver.helper.vm" in postinstall_text
    assert "ai.tirosh.vitalserver.helper.proxy" in postinstall_text
    assert "pkgutil --forget" not in postinstall_text
    assert 'rm -rf "${path}"' in postinstall_text
    assert "runtime install progress status=" not in postinstall_text
    assert "runtime install progress failureReasons=" not in postinstall_text
    assert "runtime_status=" not in postinstall_text
    assert (
        'runtime_logs="${VITALSERVER_RUNTIME_LOGS:-${product_root}/logs/runtime}"'
        in proxy_run_text
    )
    assert '"${runtime_logs}"' in proxy_run_text
    assert '"${nginx_prefix}/temp/client_body"' in proxy_run_text
    assert '"${nginx_prefix}/temp/proxy"' in proxy_run_text
    proxy_config_text = proxy_config_template.read_text(encoding="utf-8")
    assert 'error_log "${VITALSERVER_PROXY_NGINX_ERROR_LOG}";' in proxy_config_text
    assert 'access_log "${VITALSERVER_PROXY_NGINX_ACCESS_LOG}";' in proxy_config_text
    assert "client_body_temp_path temp/client_body;" in proxy_config_text
    assert "proxy_temp_path temp/proxy;" in proxy_config_text
    assert '"${vm_bin}" "runtime" "uninstall"' in uninstall_text
    assert (
        uninstall_text.index('if [ "$(id -u)" -ne 0 ]; then')
        < uninstall_text.index('exec > >(tee -a "${uninstall_log}") 2>&1')
    )
    assert 'command+=("--clean")' in uninstall_text
    assert 'command+=("--force-clean-uninstaller")' in uninstall_text
    assert (
        'vm_home="/Library/Application Support/VitalServerHelper/vm"'
        in uninstall_text
    )
    assert 'manager_app="/Applications/VitalServer Helper.app"' in uninstall_text
    assert "wait_for_helper_app_exit" in uninstall_text
    assert "/usr/bin/pgrep -f --" in uninstall_text
    assert (
        "Helper app is still running; aborting uninstall before file removal"
        in uninstall_text
    )
    assert 'VITALSERVER_VM_HOME="${vm_home}" "${command[@]}"' in uninstall_text
    assert (
        'vm_bin="${script_dir}/bin/vitalserver-vm-reset-installer"'
        in reset_for_reinstall_command_text
    )
    assert 'exec /usr/bin/sudo "$0" "$@"' in reset_for_reinstall_command_text
    assert (
        'wrapper_log="${wrapper_log_dir%/}/tirosh-vitalserver-reset-for-reinstall.log"'
        in reset_for_reinstall_command_text
    )
    assert (
        'exec > >(tee -a "${wrapper_log}") 2>&1'
        in reset_for_reinstall_command_text
    )
    assert (
        'exec > >(tee -a "${uninstall_log}") 2>&1'
        in reset_for_reinstall_command_text
    )
    assert (
        reset_for_reinstall_command_text.index('if [ "$(id -u)" -ne 0 ]; then')
        < reset_for_reinstall_command_text.index(
            'exec > >(tee -a "${uninstall_log}") 2>&1'
        )
    )
    assert (
        "runtime uninstall --force-clean-uninstaller"
        in reset_for_reinstall_command_text
    )
    assert (
        'vm_home="/Library/Application Support/VitalServerHelper/vm"'
        in reset_for_reinstall_command_text
    )
    assert (
        'manager_app="/Applications/VitalServer Helper.app"'
        in reset_for_reinstall_command_text
    )
    assert (
        'archive_name="redis-upstream-import.tar.gz"'
        in upstream_redis_backup_command_text
    )
    assert "This tool can refresh dump.rdb by running Redis SAVE" in (
        upstream_redis_backup_command_text
    )
    assert "vitalserver-upstream-redis-save" in upstream_redis_backup_command_text
    assert '"${redis_save_bin}" "${target}"' in upstream_redis_backup_command_text
    assert "redis-cli" not in upstream_redis_backup_command_text
    assert "redis://127.0.0.1:6379" in upstream_redis_backup_command_text
    assert "Type yes to continue" not in upstream_redis_backup_command_text
    assert (
        'log_file="${log_dir%/}/tirosh-vitalserver-upstream-redis-backup.log"'
        in upstream_redis_backup_command_text
    )
    assert "${UNINSTALL_LOG}" not in upstream_redis_backup_command_text
    assert (
        "choose folder with prompt"
        in upstream_redis_backup_command_text
    )
    assert (
        'if [ ! -f "${source_dir}/dump.rdb" ]; then'
        in upstream_redis_backup_command_text
    )
    assert (
        "/usr/bin/find \"${source_dir}\" -type l -print -quit"
        in upstream_redis_backup_command_text
    )
    assert (
        'refusing to overwrite existing archive: ${archive}'
        in upstream_redis_backup_command_text
    )
    assert (
        'COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \\'
        in upstream_redis_backup_command_text
    )
    assert (
        '/usr/bin/tar -czf "${archive}" -C "${source_dir}" .'
        in upstream_redis_backup_command_text
    )
    assert "Applications/VitalServer Helper.app" in components.read_text(
        encoding="utf-8"
    )
    assert os.access(postinstall, os.X_OK)
    assert os.access(proxy_run, os.X_OK)
    assert os.access(uninstall, os.X_OK)
    assert os.access(reset_for_reinstall_command, os.X_OK)
    assert os.access(upstream_redis_backup_command, os.X_OK)


def test_proxy_run_does_not_report_started_when_proxy_readiness_fails(
    tmp_path: Path,
) -> None:
    root = repo_root()
    settings = load_macos_release_settings(
        root / "config/vm-build.toml",
        root,
    )
    packaging = root / "apps/vitalserver-macos-runtime/Support/Packaging"
    proxy_run = tmp_path / "vitalserver-proxy-run"
    render_packaging_executable(
        settings,
        packaging / "proxy-run.template",
        proxy_run,
    )

    vm_home = tmp_path / "vm"
    nginx_prefix = tmp_path / "nginx"
    fake_bin = tmp_path / "bin"
    state_dir = vm_home / "data/run"
    proxy_template = vm_home / "Support/Proxy/vitalserver.conf.template"
    state_dir.mkdir(parents=True)
    proxy_template.parent.mkdir(parents=True)
    fake_bin.mkdir()
    (state_dir / "runtime-state.json").write_text(
        '{"vmIP":"192.168.64.8","guestHTTP":"200"}',
        encoding="utf-8",
    )
    proxy_template.write_text(
        """
worker_processes 1;
pid logs/nginx.pid;
events { worker_connections 64; }
http {
  server {
    listen ${VITALSERVER_PROXY_PORT};
    location = /ready { proxy_pass http://${PROXY_UPSTREAM}/ready; }
  }
}
""",
        encoding="utf-8",
    )
    fake_nginx = fake_bin / "nginx"
    fake_nginx.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
prefix=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p) prefix="$2"; shift 2 ;;
    -s)
      if [ "${2:-}" = "quit" ] && [ -s "${prefix}/logs/nginx.pid" ]; then
        kill "$(cat "${prefix}/logs/nginx.pid")" >/dev/null 2>&1 || true
        rm -f "${prefix}/logs/nginx.pid"
      fi
      exit 0
      ;;
    -t) exit 0 ;;
    *) shift ;;
  esac
done
mkdir -p "${prefix}/logs"
sleep 1000 >/dev/null 2>&1 &
echo "$!" > "${prefix}/logs/nginx.pid"
""",
        encoding="utf-8",
    )
    fake_curl = fake_bin / "curl"
    fake_curl.write_text(
        """#!/usr/bin/env bash
case "$*" in
  *127.0.0.1*) exit 22 ;;
  *) exit 0 ;;
esac
""",
        encoding="utf-8",
    )
    fake_nginx.chmod(0o755)
    fake_curl.chmod(0o755)

    stdout_path = tmp_path / "proxy-run.stdout"
    stderr_path = tmp_path / "proxy-run.stderr"
    with stdout_path.open("w", encoding="utf-8") as stdout_file, stderr_path.open(
        "w",
        encoding="utf-8",
    ) as stderr_file:
        process = subprocess.Popen(
            [str(proxy_run)],
            stdout=stdout_file,
            stderr=stderr_file,
            text=True,
            env={
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "VITALSERVER_VM_HOME": str(vm_home),
                "VITALSERVER_NGINX_PREFIX": str(nginx_prefix),
                "VITALSERVER_NGINX_BIN": str(fake_nginx),
                "VITALSERVER_PROXY_RELOAD_INTERVAL": "0.1",
            },
            start_new_session=True,
        )
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if "host proxy readiness failed after nginx configuration" in (
                stderr_path.read_text(encoding="utf-8")
            ):
                break
            time.sleep(0.05)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)

    stdout = stdout_path.read_text(encoding="utf-8")
    stderr = stderr_path.read_text(encoding="utf-8")

    assert "started proxy:" not in stdout
    assert "host proxy readiness failed after nginx configuration" in stderr
