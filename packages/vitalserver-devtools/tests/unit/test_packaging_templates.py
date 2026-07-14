from __future__ import annotations

import json
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
    platform_agent_launchd_template = (
        root
        / "apps/vitalserver-macos-runtime/launchd"
        / settings.launchd.platform_agent.template_file
    )
    proxy_config_template = root / "infra/macos-nginx/vitalserver.conf.template"
    proxy_config_template_text = proxy_config_template.read_text(encoding="utf-8")
    guest_edge_config_text = (
        root / "apps/vitalserver-macos-runtime/Support/Guest/nginx/vitalserver.conf"
    ).read_text(encoding="utf-8")
    root_compose_text = (root / "compose.yaml").read_text(encoding="utf-8")
    guest_compose_text = (
        root / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    ).read_text(encoding="utf-8")
    guest_runtime_settings = json.loads(
        (
            root / "apps/vitalserver-macos-runtime/Support/Guest/runtime-settings.json"
        ).read_text(encoding="utf-8")
    )
    guest_runtime_config = json.loads(
        (
            root / "apps/vitalserver-macos-runtime/Support/Guest/runtime-config.json"
        ).read_text(encoding="utf-8")
    )
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
    assert guest_runtime_settings["recorderIngressSendDataMode"] == "spool_and_replay"
    assert guest_runtime_settings["recorderIngressSendDataReplayBatchSize"] == 1000
    assert guest_runtime_settings["recorderIngress"]["sendDataReplayIntervalMs"] == 1000
    assert guest_runtime_settings["recorderIngress"]["rawArchiveMaxFiles"] == 24
    assert guest_runtime_config["publicHost"] == "127.0.0.1"
    assert guest_runtime_config["publicPort"] == 80
    assert guest_runtime_config["vitalServerURL"] == "http://127.0.0.1:80/"
    assert guest_runtime_config["remoteConsoleURL"] == "http://127.0.0.1:18321/"
    assert guest_runtime_settings["publicHost"] == guest_runtime_config["publicHost"]
    assert guest_runtime_settings["publicPort"] == guest_runtime_config["publicPort"]
    assert guest_runtime_settings["vitalServerURL"] == guest_runtime_config["vitalServerURL"]
    assert guest_runtime_settings["remoteConsoleURL"] == guest_runtime_config["remoteConsoleURL"]
    assert "/Library/Application Support/VitalServerHelper" in rendered
    assert_upload_proxy_streaming(proxy_config_template_text)
    assert_upload_proxy_streaming(guest_edge_config_text)
    assert_socketio_proxy_timeout(proxy_config_template_text)
    assert_socketio_proxy_timeout(guest_edge_config_text)
    assert_recorder_ingress_upload_timeout(root_compose_text)
    assert_recorder_ingress_upload_timeout(guest_compose_text)
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
    assert "ai.tirosh.vitalserver.helper.platform-agent" in postinstall_text
    platform_agent_launchd_text = platform_agent_launchd_template.read_text(
        encoding="utf-8"
    )
    assert "ai.tirosh.vitalserver.helper.platform-agent" in platform_agent_launchd_text
    assert "${VITALSERVER_PLATFORM_AGENT_BIN}" in platform_agent_launchd_text
    assert "<key>KeepAlive</key>\n  <true/>" in platform_agent_launchd_text
    assert "pkgutil --forget" not in postinstall_text
    assert 'rm -rf "${path}"' in postinstall_text
    assert "runtime install progress status=" not in postinstall_text
    assert "runtime install progress failureReasons=" not in postinstall_text
    assert "runtime_status=" not in postinstall_text
    assert (
        'runtime_logs="${VITALSERVER_RUNTIME_LOGS:-${product_root}/logs/runtime}"'
        in proxy_run_text
    )
    assert 'runtime_endpoint_file="${vm_home}/run/runtime-endpoint.json"' in proxy_run_text
    assert 'state_file="${vm_home}/data/run/runtime-observation.json"' not in proxy_run_text
    assert "read_state_value()" not in proxy_run_text
    assert "read_guest_http()" not in proxy_run_text
    assert "waiting for VM runtime observation" not in proxy_run_text
    assert "waiting for VM runtime bootstrap" not in proxy_run_text
    assert "publish_runtime_endpoint()" in proxy_run_text
    assert "clear_runtime_endpoint()" in proxy_run_text
    assert '"source":"platform-agent"' in proxy_run_text
    assert 'mv -f "${temporary}" "${runtime_endpoint_file}"' in proxy_run_text
    assert "VITALSERVER_RUNTIME_CONTROL_API_BASE_URL" not in proxy_run_text
    assert '/platform/runtime-endpoint' not in proxy_run_text
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
        'reset_bin="${script_dir}/bin/vitalserver-troubleshooting-reset-for-reinstall"'
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
        'VITALSERVER_VM_HOME="${vm_home}" "${reset_bin}"'
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
    assert (
        "vitalserver-troubleshooting-upstream-redis-save"
        in upstream_redis_backup_command_text
    )
    redis_save_timeout_default = (
        'redis_save_timeout_seconds="${UPSTREAM_REDIS_SAVE_TIMEOUT_SECONDS:-15}"'
    )
    assert redis_save_timeout_default in upstream_redis_backup_command_text
    assert "run_with_timeout()" in upstream_redis_backup_command_text
    redis_save_timeout_command = (
        'run_with_timeout "${redis_save_timeout_seconds}" '
        '"${redis_save_bin}" "${target}"'
    )
    assert redis_save_timeout_command in upstream_redis_backup_command_text
    assert "upstream redis SAVE did not complete before timeout" in (
        upstream_redis_backup_command_text
    )
    assert "SAVE is cancelled if Redis does not respond within" in (
        upstream_redis_backup_command_text
    )
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
    (state_dir / "vm-ip").write_text("192.168.64.8\n", encoding="utf-8")
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
  */platform/runtime-endpoint*)
    printf '{"state":"loaded","read":{"state":"loaded","address":"192.168.64.8"}}'
    exit 0
    ;;
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


def test_proxy_run_requires_recorder_ingress_health_on_upstream(
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
    (state_dir / "vm-ip").write_text("192.168.64.8\n", encoding="utf-8")
    proxy_template.write_text(
        """
worker_processes 1;
pid logs/nginx.pid;
events { worker_connections 64; }
http {
  server {
    listen ${VITALSERVER_PROXY_PORT};
    location = /ready { proxy_pass http://${PROXY_UPSTREAM}/ready; }
    location = /recorder-ingress/health {
      proxy_pass http://${PROXY_UPSTREAM}/recorder-ingress/health;
    }
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
    -s) exit 0 ;;
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
  */platform/runtime-endpoint*)
    printf '{"state":"loaded","read":{"state":"loaded","address":"192.168.64.8"}}'
    exit 0
    ;;
  *192.168.64.8:80/recorder-ingress/health*) exit 22 ;;
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
            if "waiting for VM upstream readiness" in (
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
    assert "waiting for VM upstream readiness: http://192.168.64.8:80/" in stderr


def test_proxy_run_publishes_durable_runtime_endpoint_and_routes_from_it(
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
    capture_file = tmp_path / "curl-calls.txt"
    endpoint_file = vm_home / "run/runtime-endpoint.json"
    state_dir.mkdir(parents=True)
    proxy_template.parent.mkdir(parents=True)
    fake_bin.mkdir()
    (state_dir / "runtime-observation.json").write_text(
        '{"vmIP":"192.168.64.9","guestHTTP":"503"}',
        encoding="utf-8",
    )
    (state_dir / "vm-ip").write_text("192.168.64.9\n", encoding="utf-8")
    proxy_template.write_text(
        """
worker_processes 1;
pid logs/nginx.pid;
events { worker_connections 64; }
http { server { listen ${VITALSERVER_PROXY_PORT}; } }
""",
        encoding="utf-8",
    )
    fake_nginx = fake_bin / "nginx"
    fake_nginx.write_text(
        """#!/usr/bin/env bash
exit 0
""",
        encoding="utf-8",
    )
    fake_curl = fake_bin / "curl"
    fake_curl.write_text(
        """#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_CAPTURE_FILE}"
case "$*" in
  */platform/runtime-endpoint*)
    if [[ "$*" != *"-X PUT"* ]]; then
      printf '{"state":"loaded","read":{"state":"loaded","address":"192.168.64.10"}}'
    fi
    ;;
esac
exit 0
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
                "CURL_CAPTURE_FILE": str(capture_file),
                "VITALSERVER_VM_HOME": str(vm_home),
                "VITALSERVER_NGINX_PREFIX": str(nginx_prefix),
                "VITALSERVER_NGINX_BIN": str(fake_nginx),
                "VITALSERVER_PROXY_RELOAD_INTERVAL": "0.1",
                "VITALSERVER_RUNTIME_CONTROL_API_BASE_URL": "http://127.0.0.1:18321",
            },
            start_new_session=True,
        )
        endpoint_document: dict[str, str] | None = None
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            stdout = stdout_path.read_text(encoding="utf-8")
            if endpoint_file.exists() and "started proxy:" in stdout:
                endpoint_document = json.loads(endpoint_file.read_text(encoding="utf-8"))
                break
            time.sleep(0.05)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=5)

    calls = capture_file.read_text(encoding="utf-8")
    stdout = stdout_path.read_text(encoding="utf-8")
    stderr = stderr_path.read_text(encoding="utf-8")
    assert endpoint_document == {
        "address": "192.168.64.9",
        "source": "platform-agent",
        "state": "loaded",
    }
    assert not endpoint_file.exists()
    assert "/platform/runtime-endpoint" not in calls
    assert "192.168.64.9:80" in calls
    assert "started proxy: http://localhost:" in stdout
    assert "-> http://192.168.64.9:80" in stdout
    assert "waiting for VM runtime observation" not in stderr
    assert "waiting for VM runtime bootstrap" not in stderr


def assert_upload_proxy_streaming(config_text: str) -> None:
    """Assert VitalServer upload endpoints opt into large streaming bodies."""

    assert "location = /upload {" in config_text
    assert "location = /upload_vital.php {" in config_text
    assert config_text.count("client_max_body_size 0;") == 2
    assert config_text.count("proxy_request_buffering off;") == 2
    assert config_text.count("client_body_timeout 1h;") == 2
    assert config_text.count("proxy_send_timeout 1h;") == 3
    assert config_text.count("proxy_read_timeout 1h;") == 3


def assert_socketio_proxy_timeout(config_text: str) -> None:
    """Assert VRecorder Socket.IO connections are not cut by nginx defaults."""

    assert "proxy_send_timeout 1h;" in location_block(config_text, "/socket.io/")
    assert "proxy_read_timeout 1h;" in location_block(config_text, "/socket.io/")


def location_block(config_text: str, location: str) -> str:
    start = config_text.find(f"location {location}")
    assert start >= 0
    candidates = [
        index
        for index in [
            config_text.find("\n        location ", start + 1),
            config_text.find("\n  location ", start + 1),
        ]
        if index >= 0
    ]
    end = min(candidates) if candidates else config_text.find("\n    }", start + 1)
    if end < 0:
        end = config_text.find("\n}", start + 1)
    assert end >= 0
    return config_text[start:end]


def assert_recorder_ingress_upload_timeout(compose_text: str) -> None:
    """Assert recorder ingress keeps long uploads and parser waits open."""

    upstream_timeout = (
        'RECORDER_INGRESS_UPSTREAM_TIMEOUT_MS: '
        '"${RECORDER_INGRESS_UPSTREAM_TIMEOUT_MS:-3600000}"'
    )
    assert (
        upstream_timeout in compose_text
    )
