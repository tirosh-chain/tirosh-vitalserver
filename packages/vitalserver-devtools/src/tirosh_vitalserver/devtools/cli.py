from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    default_config_path,
    parse_bool,
    run_config_value,
)
from tirosh_vitalserver.devtools.environment import (
    run_env_bootstrap,
    run_env_doctor,
    run_require_uv,
)
from tirosh_vitalserver.devtools.guest_image.cloud_init import run_cloud_init
from tirosh_vitalserver.devtools.guest_image.rootfs_base import (
    add_rootfs_base_arguments,
    run_rootfs_base,
)
from tirosh_vitalserver.devtools.guest_image.ubuntu import run_ubuntu
from tirosh_vitalserver.devtools.guest_services.deploy_bundle import run_guest_deploy
from tirosh_vitalserver.devtools.guest_services.docker_images import run_docker_images
from tirosh_vitalserver.devtools.host_proxy.local_proxy import (
    run_proxy_clean,
    run_proxy_config,
    run_proxy_plist,
    run_proxy_port_check,
    run_proxy_reload,
    run_proxy_start,
    run_proxy_status,
    run_proxy_stop,
    run_proxy_stop_orphans,
    run_proxy_test,
    run_proxy_write_config,
)
from tirosh_vitalserver.devtools.host_proxy.nginx_bundle import run_nginx_bundle
from tirosh_vitalserver.devtools.release import (
    run_release_dmg,
    run_release_pkg,
    run_release_update_bundle,
)
from tirosh_vitalserver.devtools.release.macos.installed_runtime import (
    run_installed_health,
    run_installed_status,
)
from tirosh_vitalserver.devtools.release.macos.runtime_lifecycle import (
    run_macos_runtime_build,
    run_macos_runtime_control,
    run_macos_runtime_health,
    run_macos_runtime_ip,
    run_macos_runtime_require_bridged_identity,
    run_macos_runtime_sign,
    run_macos_runtime_start_detached,
    run_macos_runtime_sync_release,
    run_macos_runtime_wait_http,
    run_macos_runtime_wait_ip,
    run_macos_runtime_wait_rootfs_ready,
)
from tirosh_vitalserver.devtools.release.macos.use_cases import (
    run_macos_app,
    run_macos_package_clean,
    run_macos_package_install,
    run_release_update_bundle_verify,
)
from tirosh_vitalserver.devtools.toolchain.git_checks import run_require_branch
from tirosh_vitalserver.devtools.toolchain.token_template import run_render_template
from tirosh_vitalserver.devtools.update_bundle import (
    run_build_update_bundle,
    run_verify_update_bundle,
)
from tirosh_vitalserver.devtools.workspace import (
    run_compose,
    run_open,
    run_python_tool,
)


def main() -> int:
    parser = argparse.ArgumentParser(prog="vitalserver-devtools")
    parser.add_argument(
        "--config",
        type=Path,
        default=default_config_path(),
        help="build config TOML path",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    config_value = subparsers.add_parser(
        "config-value",
        help="print a scalar value from the build config TOML",
    )
    config_value.add_argument("key")

    ubuntu = subparsers.add_parser(
        "ubuntu",
        help="download and prepare Ubuntu VM boot assets",
    )
    ubuntu.add_argument("--runtime-dir", type=Path)
    ubuntu.add_argument("--rootfs-size")
    ubuntu.add_argument("--recreate-rootfs", type=parse_bool)
    ubuntu.add_argument("--disk-image-name")

    docker_images = subparsers.add_parser(
        "docker-images",
        help="build the air-gapped Docker image bundle",
    )
    docker_images.add_argument("--bundle-path", type=Path)
    docker_images.add_argument("--platform")
    docker_images.add_argument("--compression-threads", type=int)

    rootfs_base = subparsers.add_parser(
        "rootfs-base",
        help="compress a clean VM disk into an immutable rootfs base artifact",
    )
    add_rootfs_base_arguments(rootfs_base)

    nginx_bundle = subparsers.add_parser(
        "nginx-bundle",
        help="build a self-contained nginx bundle for the macOS host proxy",
    )
    nginx_bundle.add_argument("--bundle-dir", required=True, type=Path)
    nginx_bundle.add_argument("--binary")
    nginx_bundle.add_argument("--expected-version")

    cloud_init = subparsers.add_parser(
        "cloud-init",
        help="create a NoCloud seed ISO for the VM",
    )
    cloud_init.add_argument("--runtime-dir", type=Path)
    cloud_init.add_argument("--seed-dir", type=Path)
    cloud_init.add_argument("--seed-iso", type=Path)
    cloud_init.add_argument("--hostname")
    cloud_init.add_argument("--instance-id")
    cloud_init.add_argument("--username")
    cloud_init.add_argument("--password")
    cloud_init.add_argument("--ssh-key", type=Path)
    cloud_init.add_argument("--run-bootstrap", type=parse_bool)
    cloud_init.add_argument("--share-tag")
    cloud_init.add_argument("--share-mount")
    cloud_init.add_argument("--bootstrap-script")

    guest_deploy = subparsers.add_parser(
        "guest-deploy",
        help="stage the Linux guest deployment bundle for a local VM home",
    )
    guest_deploy.add_argument("--vm-home", type=Path, required=True)
    guest_deploy.add_argument("--runtime-dir", type=Path, required=True)
    guest_deploy.add_argument("--deploy-dir", type=Path)
    guest_deploy.add_argument("--docker-bundle", type=Path)

    require_branch = subparsers.add_parser(
        "require-branch",
        help="fail unless the current git branch matches the expected branch",
    )
    require_branch.add_argument("--branch", required=True)

    macos_app = subparsers.add_parser(
        "macos-app",
        help="build and sign the macOS helper app bundle from release.json",
    )
    macos_app.add_argument("--release-file", type=Path, required=True)
    macos_app.add_argument("--sdkroot")
    macos_app.add_argument("--clang-module-cache")
    macos_app.add_argument("--codesign-identity", default="-")

    installed_status = subparsers.add_parser(
        "macos-installed-status",
        help="print installed macOS runtime files and launchd status",
    )
    installed_status.add_argument(
        "--fail-on-unhealthy",
        action="store_true",
    )

    installed_health = subparsers.add_parser(
        "macos-installed-health",
        help="check installed macOS runtime HTTP health",
    )
    installed_health.add_argument("--proxy-port", required=True)

    runtime_build = subparsers.add_parser(
        "macos-runtime-build",
        help="sync release metadata and build the macOS runtime",
    )
    runtime_build.add_argument("--release-file", type=Path, required=True)
    runtime_build.add_argument("--sdkroot")
    runtime_build.add_argument("--clang-module-cache")

    runtime_sync_release = subparsers.add_parser(
        "macos-runtime-sync-release",
        help="sync release metadata into generated Swift sources",
    )
    runtime_sync_release.add_argument("--release-file", type=Path, required=True)

    runtime_sign = subparsers.add_parser(
        "macos-runtime-sign",
        help="sign the macOS runtime CLI",
    )
    runtime_sign.add_argument("--identity", required=True)
    runtime_sign.add_argument("--entitlements", required=True)

    runtime_bridged_preflight = subparsers.add_parser(
        "macos-runtime-require-bridged-identity",
        help="fail unless bridged mode has a real codesign identity",
    )
    runtime_bridged_preflight.add_argument("--identity", required=True)

    runtime_control = subparsers.add_parser(
        "macos-runtime-control",
        help="run a macOS runtime CLI command with VITALSERVER_VM_HOME",
    )
    runtime_control.add_argument("--vm-home", type=Path, required=True)
    runtime_control.add_argument("runtime_args", nargs=argparse.REMAINDER)

    runtime_start_detached = subparsers.add_parser(
        "macos-runtime-start-detached",
        help="start the macOS runtime launcher in the background",
    )
    runtime_start_detached.add_argument("--vm-home", type=Path, required=True)

    runtime_ip = subparsers.add_parser(
        "macos-runtime-ip",
        help="print the guest VM IP recorded by the runtime",
    )
    runtime_ip.add_argument("--vm-home", type=Path, required=True)

    runtime_wait_ip = subparsers.add_parser(
        "macos-runtime-wait-ip",
        help="wait until the guest VM IP file is available",
    )
    runtime_wait_ip.add_argument("--vm-home", type=Path, required=True)
    runtime_wait_ip.add_argument("--timeout", type=int, required=True)

    runtime_wait_http = subparsers.add_parser(
        "macos-runtime-wait-http",
        help="wait until guest HTTP responds",
    )
    runtime_wait_http.add_argument("--vm-home", type=Path, required=True)
    runtime_wait_http.add_argument("--timeout", type=int, required=True)

    runtime_wait_rootfs = subparsers.add_parser(
        "macos-runtime-wait-rootfs-ready",
        help="wait until the air-gapped rootfs marker is available",
    )
    runtime_wait_rootfs.add_argument("--vm-home", type=Path, required=True)
    runtime_wait_rootfs.add_argument("--timeout", type=int, required=True)

    runtime_health = subparsers.add_parser(
        "macos-runtime-health",
        help="check local development VM and proxy health",
    )
    runtime_health.add_argument("--vm-home", type=Path, required=True)
    runtime_health.add_argument("--proxy-port", required=True)

    update_bundle = subparsers.add_parser(
        "update-bundle",
        help="build an update bundle manifest and checksums",
    )
    update_bundle.add_argument("--version", required=True)
    update_bundle.add_argument("--runtime-version")
    update_bundle.add_argument("--bundle-name")
    update_bundle.add_argument("--channel", choices=["stable", "dev"], default="stable")
    update_bundle.add_argument("--release-label")
    update_bundle.add_argument("--min-updater-version")
    update_bundle.add_argument("--requires-guest-activation", type=parse_bool)
    update_bundle.add_argument(
        "--requires-two-phase-update",
        type=parse_bool,
        default=False,
    )
    update_bundle.add_argument(
        "--bundle-kind",
        choices=["product-update", "vm-image-update"],
        default="product-update",
    )
    update_bundle.add_argument("--helper-version")
    update_bundle.add_argument("--target-platform", required=True)
    update_bundle.add_argument(
        "--component",
        action="append",
        default=[],
        help="component version as key=value, e.g. vmDriver=0.2.0+macos.1",
    )
    update_bundle.add_argument("--output-dir", type=Path, required=True)
    update_bundle.add_argument("--rootfs-base", type=Path)
    update_bundle.add_argument("--app-bundle", type=Path)
    update_bundle.add_argument("--runtime-tools", type=Path)
    update_bundle.add_argument("--nginx-bundle", type=Path)
    update_bundle.add_argument("--guest-deploy", type=Path)
    update_bundle.add_argument("--migration", action="append", type=Path, default=[])

    release_update_bundle = subparsers.add_parser(
        "release-update-bundle",
        help="build a release update bundle from release.json",
    )
    release_update_bundle.add_argument("--release-file", type=Path, required=True)
    release_update_bundle.add_argument("--bundle-name")
    release_update_bundle.add_argument(
        "--bundle-kind",
        choices=["product-update", "vm-image-update"],
        default="product-update",
    )
    release_update_bundle.add_argument("--target-platform")
    release_update_bundle.add_argument("--output-dir", type=Path)
    release_update_bundle.add_argument("--rootfs-base")
    release_update_bundle.add_argument(
        "--migration",
        action="append",
        type=Path,
        default=[],
    )
    release_update_bundle.add_argument(
        "--requires-two-phase-update",
        type=parse_bool,
        default=False,
    )
    release_update_bundle.add_argument("--compression-threads", type=int)
    release_update_bundle.add_argument("--sdkroot")
    release_update_bundle.add_argument(
        "--clang-module-cache",
    )
    release_update_bundle.add_argument("--codesign-identity", default="-")
    release_update_bundle.add_argument("--nginx-binary")
    release_update_bundle.add_argument("--nginx-expected-version")
    release_update_bundle.add_argument("--docker-platform")

    release_update_bundle_verify = subparsers.add_parser(
        "release-update-bundle-verify",
        help="verify a release update bundle from release.json defaults",
    )
    release_update_bundle_verify.add_argument(
        "--release-file",
        type=Path,
        required=True,
    )
    release_update_bundle_verify.add_argument("--bundle-name")
    release_update_bundle_verify.add_argument(
        "--bundle-kind",
        choices=["product-update", "vm-image-update"],
        default="product-update",
    )

    release_pkg = subparsers.add_parser(
        "release-pkg",
        help="build a macOS runtime pkg from release.json",
    )
    add_release_package_arguments(release_pkg)

    release_dmg = subparsers.add_parser(
        "release-dmg",
        help="build a macOS runtime dmg from release.json",
    )
    add_release_package_arguments(release_dmg)
    release_dmg.set_defaults(output_kind="dmg")

    macos_package_clean = subparsers.add_parser(
        "macos-package-clean",
        help="remove generated macOS package artifacts",
    )
    macos_package_clean.add_argument("--release-file", type=Path, required=True)

    macos_package_install = subparsers.add_parser(
        "macos-package-install",
        help="install the macOS runtime pkg computed from release.json",
    )
    macos_package_install.add_argument("--release-file", type=Path, required=True)
    macos_package_install.add_argument("--install-settings")

    verify_update_bundle = subparsers.add_parser(
        "verify-update-bundle",
        help="verify an update bundle manifest and checksums",
    )
    verify_update_bundle.add_argument("bundle_path", type=Path)

    render_template = subparsers.add_parser(
        "render-template",
        help="render a small ${VAR} template",
    )
    render_template.add_argument("--template", required=True, type=Path)
    render_template.add_argument("--output", required=True, type=Path)
    render_template.add_argument("--var", action="append", default=[])

    proxy_config = subparsers.add_parser("proxy-config")
    add_proxy_arguments(proxy_config)

    proxy_write_config = subparsers.add_parser("proxy-write-config")
    add_proxy_arguments(proxy_write_config)

    proxy_test = subparsers.add_parser("proxy-test")
    add_proxy_arguments(proxy_test)

    proxy_start = subparsers.add_parser("proxy-start")
    add_proxy_arguments(proxy_start)

    proxy_port_check = subparsers.add_parser("proxy-port-check")
    add_proxy_arguments(proxy_port_check)

    proxy_stop = subparsers.add_parser("proxy-stop")
    add_proxy_arguments(proxy_stop)

    proxy_stop_orphans = subparsers.add_parser("proxy-stop-orphans")
    add_proxy_arguments(proxy_stop_orphans)

    proxy_clean = subparsers.add_parser("proxy-clean")
    add_proxy_arguments(proxy_clean)

    proxy_reload = subparsers.add_parser("proxy-reload")
    add_proxy_arguments(proxy_reload)

    proxy_status = subparsers.add_parser("proxy-status")
    add_proxy_arguments(proxy_status)

    proxy_plist = subparsers.add_parser("proxy-plist")
    add_proxy_arguments(proxy_plist)

    env_bootstrap = subparsers.add_parser("env-bootstrap")
    add_environment_arguments(env_bootstrap)

    env_doctor = subparsers.add_parser("env-doctor")
    add_environment_arguments(env_doctor)

    require_uv = subparsers.add_parser("require-uv")
    add_environment_arguments(require_uv)

    compose = subparsers.add_parser("compose")
    add_compose_arguments(compose)
    compose.add_argument("compose_args", nargs=argparse.REMAINDER)

    open_app = subparsers.add_parser("open")
    open_app.add_argument("--port", required=True)

    python_tool = subparsers.add_parser("python-tool")
    python_tool.add_argument("--uv", default="uv")
    python_tool.add_argument("tool_args", nargs=argparse.REMAINDER)

    args = parser.parse_args()

    if args.command == "config-value":
        return run_config_value(args)
    if args.command == "ubuntu":
        return run_ubuntu(args)
    if args.command == "docker-images":
        return run_docker_images(args)
    if args.command == "rootfs-base":
        return run_rootfs_base(args)
    if args.command == "nginx-bundle":
        return run_nginx_bundle(args)
    if args.command == "cloud-init":
        return run_cloud_init(args)
    if args.command == "guest-deploy":
        return run_guest_deploy(args)
    if args.command == "require-branch":
        return run_require_branch(args)
    if args.command == "macos-app":
        return run_macos_app(args)
    if args.command == "macos-installed-status":
        return run_installed_status(args)
    if args.command == "macos-installed-health":
        return run_installed_health(args)
    if args.command == "macos-runtime-build":
        return run_macos_runtime_build(args)
    if args.command == "macos-runtime-sync-release":
        return run_macos_runtime_sync_release(args)
    if args.command == "macos-runtime-sign":
        return run_macos_runtime_sign(args)
    if args.command == "macos-runtime-require-bridged-identity":
        return run_macos_runtime_require_bridged_identity(args)
    if args.command == "macos-runtime-control":
        return run_macos_runtime_control(args)
    if args.command == "macos-runtime-start-detached":
        return run_macos_runtime_start_detached(args)
    if args.command == "macos-runtime-ip":
        return run_macos_runtime_ip(args)
    if args.command == "macos-runtime-wait-ip":
        return run_macos_runtime_wait_ip(args)
    if args.command == "macos-runtime-wait-http":
        return run_macos_runtime_wait_http(args)
    if args.command == "macos-runtime-wait-rootfs-ready":
        return run_macos_runtime_wait_rootfs_ready(args)
    if args.command == "macos-runtime-health":
        return run_macos_runtime_health(args)
    if args.command == "update-bundle":
        return run_build_update_bundle(args)
    if args.command == "release-update-bundle":
        return run_release_update_bundle(args)
    if args.command == "release-update-bundle-verify":
        return run_release_update_bundle_verify(args)
    if args.command == "release-pkg":
        return run_release_pkg(args)
    if args.command == "release-dmg":
        return run_release_dmg(args)
    if args.command == "macos-package-clean":
        return run_macos_package_clean(args)
    if args.command == "macos-package-install":
        return run_macos_package_install(args)
    if args.command == "verify-update-bundle":
        return run_verify_update_bundle(args)
    if args.command == "render-template":
        return run_render_template(args)
    if args.command == "proxy-config":
        return run_proxy_config(args)
    if args.command == "proxy-write-config":
        return run_proxy_write_config(args)
    if args.command == "proxy-test":
        return run_proxy_test(args)
    if args.command == "proxy-start":
        return run_proxy_start(args)
    if args.command == "proxy-port-check":
        return run_proxy_port_check(args)
    if args.command == "proxy-stop":
        return run_proxy_stop(args)
    if args.command == "proxy-stop-orphans":
        return run_proxy_stop_orphans(args)
    if args.command == "proxy-clean":
        return run_proxy_clean(args)
    if args.command == "proxy-reload":
        return run_proxy_reload(args)
    if args.command == "proxy-status":
        return run_proxy_status(args)
    if args.command == "proxy-plist":
        return run_proxy_plist(args)
    if args.command == "env-bootstrap":
        return run_env_bootstrap(args)
    if args.command == "env-doctor":
        return run_env_doctor(args)
    if args.command == "require-uv":
        return run_require_uv(args)
    if args.command == "compose":
        return run_compose(args)
    if args.command == "open":
        return run_open(args)
    if args.command == "python-tool":
        return run_python_tool(args)
    parser.error(f"unsupported command: {args.command}")
    return 2


def add_release_package_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--release-file", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.set_defaults(output_kind="pkg")
    parser.add_argument("--rootfs-base", type=Path, required=True)
    parser.add_argument("--golden-runtime-dir", type=Path, required=True)
    parser.add_argument("--proxy-port", required=True)
    parser.add_argument("--compression-threads", type=int)
    parser.add_argument("--sdkroot")
    parser.add_argument("--clang-module-cache")
    parser.add_argument("--codesign-identity", default="-")
    parser.add_argument("--nginx-binary")
    parser.add_argument("--nginx-expected-version")
    parser.add_argument("--docker-platform")


def add_proxy_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--runtime-dir", default=".tmp/macos-nginx")
    parser.add_argument("--config", default=".tmp/macos-nginx/vitalserver.conf")
    parser.add_argument("--port", default="80")
    parser.add_argument("--bind-host", default="127.0.0.1")
    parser.add_argument("--http-port", default="18080")
    parser.add_argument("--upstream", default="127.0.0.1:18080")
    parser.add_argument("--trust-proxy", default="1")
    parser.add_argument("--nginx-bin", default="/opt/homebrew/bin/nginx")
    parser.add_argument(
        "--nginx-conf",
        default="/Library/Application Support/TiroshVitalServer/nginx/vitalserver.conf",
    )
    parser.add_argument(
        "--nginx-prefix",
        default="/Library/Application Support/TiroshVitalServer/nginx",
    )


def add_environment_arguments(parser: argparse.ArgumentParser) -> None:
    add_proxy_arguments(parser)
    parser.add_argument("--python", default="python3")
    parser.add_argument("--uv", default="uv")
    parser.add_argument("--compose", default="docker compose")


def add_compose_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--compose", default="docker compose")
    parser.add_argument("--bind-host", default="127.0.0.1")
    parser.add_argument("--http-port", default="18080")
    parser.add_argument("--redis-host", default="redis")
    parser.add_argument("--redis-port", default="6379")
    parser.add_argument("--trust-proxy", default="1")
