from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.devtools.application import inputs as usecase_inputs
from tirosh_vitalserver.devtools.application.usecases import (
    build_config as build_config_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    environment as environment_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    guest_image as guest_image_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    guest_services as guest_services_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    host_proxy as host_proxy_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    macos_app as macos_app_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    macos_installed_runtime as installed_runtime_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    macos_package as macos_package_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    macos_runtime as macos_runtime_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    macos_update_bundle as macos_update_bundle_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    toolchain as toolchain_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    update_bundle as update_bundle_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    workspace as workspace_usecases,
)
from tirosh_vitalserver.devtools.config.build_toml import (
    default_config_path,
)
from tirosh_vitalserver.devtools.core.errors import DomainError


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
    config_value.set_defaults(
        handler=lambda args: build_config_usecases.print_config_value(
            usecase_inputs.ConfigValueInput(
                config=args.config,
                key=args.key,
            )
        )
    )

    ubuntu = subparsers.add_parser(
        "ubuntu",
        help="download and prepare Ubuntu VM boot assets",
    )
    ubuntu.add_argument("--runtime-dir", type=Path)
    ubuntu.add_argument("--rootfs-size")
    ubuntu.add_argument("--recreate-rootfs", type=parse_bool)
    ubuntu.add_argument("--disk-image-name")
    ubuntu.set_defaults(
        handler=lambda args: guest_image_usecases.prepare_ubuntu_boot_assets(
            usecase_inputs.UbuntuBootAssetsInput(
                config=args.config,
                runtime_dir=args.runtime_dir,
                rootfs_size=args.rootfs_size,
                recreate_rootfs=args.recreate_rootfs,
                disk_image_name=args.disk_image_name,
            )
        )
    )

    docker_images = subparsers.add_parser(
        "docker-images",
        help="build the air-gapped Docker image bundle",
    )
    docker_images.add_argument("--bundle-path", type=Path)
    docker_images.add_argument("--platform")
    docker_images.add_argument("--compression-threads", type=int)
    docker_images.set_defaults(
        handler=lambda args: guest_services_usecases.build_docker_image_bundle(
            usecase_inputs.DockerImageBundleInput(
                config=args.config,
                bundle_path=args.bundle_path,
                platform=args.platform,
                compression_threads=args.compression_threads,
            )
        )
    )

    rootfs_base = subparsers.add_parser(
        "rootfs-base",
        help="compress a clean VM disk into an immutable rootfs base artifact",
    )
    add_rootfs_base_arguments(rootfs_base)
    rootfs_base.set_defaults(
        handler=lambda args: guest_image_usecases.compress_rootfs_base(
            usecase_inputs.RootfsBaseInput(
                source=args.source,
                output=args.output,
                force=args.force,
                compression_threads=args.compression_threads,
            )
        )
    )

    nginx_bundle = subparsers.add_parser(
        "nginx-bundle",
        help="build a self-contained nginx bundle for the macOS host proxy",
    )
    nginx_bundle.add_argument("--bundle-dir", required=True, type=Path)
    nginx_bundle.add_argument("--binary")
    nginx_bundle.add_argument("--expected-version")
    nginx_bundle.add_argument("--release-file", type=Path)
    nginx_bundle.set_defaults(
        handler=lambda args: host_proxy_usecases.build_nginx(
            nginx_bundle_input(args)
        )
    )

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
    cloud_init.set_defaults(
        handler=lambda args: guest_image_usecases.create_cloud_init_seed(
            usecase_inputs.CloudInitInput(
                config=args.config,
                runtime_dir=args.runtime_dir,
                seed_dir=args.seed_dir,
                seed_iso=args.seed_iso,
                hostname=args.hostname,
                instance_id=args.instance_id,
                username=args.username,
                password=args.password,
                ssh_key=args.ssh_key,
                run_bootstrap=args.run_bootstrap,
                share_tag=args.share_tag,
                share_mount=args.share_mount,
                bootstrap_script=args.bootstrap_script,
            )
        )
    )

    guest_deploy = subparsers.add_parser(
        "guest-deploy",
        help="stage the Linux guest deployment bundle for a local VM home",
    )
    guest_deploy.add_argument("--vm-home", type=Path, required=True)
    guest_deploy.add_argument("--runtime-dir", type=Path, required=True)
    guest_deploy.add_argument("--deploy-dir", type=Path)
    guest_deploy.add_argument("--docker-bundle", type=Path)
    guest_deploy.set_defaults(
        handler=lambda args: guest_services_usecases.stage_guest_deployment(
            usecase_inputs.GuestDeploymentInput(
                config=args.config,
                vm_home=args.vm_home,
                runtime_dir=args.runtime_dir,
                deploy_dir=args.deploy_dir,
                docker_bundle=args.docker_bundle,
            )
        )
    )

    require_branch = subparsers.add_parser(
        "require-branch",
        help="fail unless the current git branch matches the expected branch",
    )
    require_branch.add_argument("--branch", required=True)
    require_branch.set_defaults(
        handler=lambda args: toolchain_usecases.require_git_branch(
            usecase_inputs.RequireGitBranchInput(branch=args.branch)
        )
    )

    macos_app = subparsers.add_parser(
        "macos-app",
        help="build and sign the macOS helper app bundle from release.json",
    )
    macos_app.add_argument("--release-file", type=Path, required=True)
    macos_app.add_argument("--sdkroot")
    macos_app.add_argument("--clang-module-cache")
    macos_app.add_argument("--codesign-identity", default="-")
    macos_app.set_defaults(
        handler=lambda args: macos_app_usecases.build_helper(
            macos_app_input(args)
        )
    )

    installed_status = subparsers.add_parser(
        "macos-installed-status",
        help="print installed macOS runtime files and launchd status",
    )
    installed_status.add_argument(
        "--fail-on-unhealthy",
        action="store_true",
    )
    installed_status.set_defaults(
        handler=lambda args: installed_runtime_usecases.inspect_installed_runtime(
            usecase_inputs.InstalledStatusInput(
                config=args.config,
                fail_on_unhealthy=args.fail_on_unhealthy,
            )
        )
    )

    installed_health = subparsers.add_parser(
        "macos-installed-health",
        help="check installed macOS runtime HTTP health",
    )
    installed_health.add_argument("--proxy-port", required=True)
    installed_health.set_defaults(
        handler=(
            lambda args: installed_runtime_usecases.check_installed_runtime_health(
                usecase_inputs.InstalledHealthInput(
                    config=args.config,
                    proxy_port=args.proxy_port,
                )
            )
        )
    )

    runtime_build = subparsers.add_parser(
        "macos-runtime-build",
        help="sync release metadata and build the macOS runtime",
    )
    runtime_build.add_argument("--release-file", type=Path, required=True)
    runtime_build.add_argument("--sdkroot")
    runtime_build.add_argument("--clang-module-cache")
    runtime_build.set_defaults(
        handler=lambda args: macos_runtime_usecases.build(
            usecase_inputs.RuntimeBuildInput(
                config=args.config,
                release_file=args.release_file,
                sdkroot=args.sdkroot,
                clang_module_cache=args.clang_module_cache,
            )
        )
    )

    runtime_sync_release = subparsers.add_parser(
        "macos-runtime-sync-release",
        help="sync release metadata into generated Swift sources",
    )
    runtime_sync_release.add_argument("--release-file", type=Path, required=True)
    runtime_sync_release.set_defaults(
        handler=lambda args: macos_runtime_usecases.sync_release_sources(
            usecase_inputs.RuntimeSyncReleaseInput(
                config=args.config,
                release_file=args.release_file,
            )
        ),
    )

    runtime_sign = subparsers.add_parser(
        "macos-runtime-sign",
        help="sign the macOS runtime CLI",
    )
    runtime_sign.add_argument("--identity", required=True)
    runtime_sign.add_argument("--entitlements", required=True)
    runtime_sign.set_defaults(
        handler=lambda args: macos_runtime_usecases.sign(
            usecase_inputs.RuntimeSignInput(
                config=args.config,
                identity=args.identity,
                entitlements=args.entitlements,
            )
        )
    )

    runtime_bridged_preflight = subparsers.add_parser(
        "macos-runtime-require-bridged-identity",
        help="fail unless bridged mode has a real codesign identity",
    )
    runtime_bridged_preflight.add_argument("--identity", required=True)
    runtime_bridged_preflight.set_defaults(
        handler=lambda args: macos_runtime_usecases.require_bridged_identity(
            usecase_inputs.RequireBridgedIdentityInput(identity=args.identity)
        ),
    )

    runtime_control = subparsers.add_parser(
        "macos-runtime-control",
        help="run a macOS runtime CLI command with VITALSERVER_VM_HOME",
    )
    runtime_control.add_argument("--vm-home", type=Path, required=True)
    runtime_control.add_argument("runtime_args", nargs=argparse.REMAINDER)
    runtime_control.set_defaults(
        handler=lambda args: macos_runtime_usecases.control(
            usecase_inputs.RuntimeControlInput(
                config=args.config,
                vm_home=args.vm_home,
                runtime_args=args.runtime_args,
            )
        )
    )

    runtime_start_detached = subparsers.add_parser(
        "macos-runtime-start-detached",
        help="start the macOS runtime launcher in the background",
    )
    runtime_start_detached.add_argument("--vm-home", type=Path, required=True)
    runtime_start_detached.set_defaults(
        handler=lambda args: macos_runtime_usecases.start_detached(
            usecase_inputs.RuntimeVmHomeInput(
                config=args.config,
                vm_home=args.vm_home,
            )
        ),
    )

    runtime_ip = subparsers.add_parser(
        "macos-runtime-ip",
        help="print the guest VM IP recorded by the runtime",
    )
    runtime_ip.add_argument("--vm-home", type=Path, required=True)
    runtime_ip.set_defaults(
        handler=lambda args: macos_runtime_usecases.print_ip(
            usecase_inputs.RuntimeVmHomeInput(
                config=args.config,
                vm_home=args.vm_home,
            )
        )
    )

    runtime_wait_ip = subparsers.add_parser(
        "macos-runtime-wait-ip",
        help="wait until the guest VM IP file is available",
    )
    runtime_wait_ip.add_argument("--vm-home", type=Path, required=True)
    runtime_wait_ip.add_argument("--timeout", type=int, required=True)
    runtime_wait_ip.set_defaults(
        handler=lambda args: macos_runtime_usecases.wait_ip(
            runtime_wait_input(args)
        )
    )

    runtime_wait_http = subparsers.add_parser(
        "macos-runtime-wait-http",
        help="wait until guest HTTP responds",
    )
    runtime_wait_http.add_argument("--vm-home", type=Path, required=True)
    runtime_wait_http.add_argument("--timeout", type=int, required=True)
    runtime_wait_http.set_defaults(
        handler=lambda args: macos_runtime_usecases.wait_http(
            runtime_wait_input(args)
        )
    )

    runtime_wait_rootfs = subparsers.add_parser(
        "macos-runtime-wait-rootfs-ready",
        help="wait until the air-gapped rootfs marker is available",
    )
    runtime_wait_rootfs.add_argument("--vm-home", type=Path, required=True)
    runtime_wait_rootfs.add_argument("--timeout", type=int, required=True)
    runtime_wait_rootfs.set_defaults(
        handler=lambda args: macos_runtime_usecases.wait_rootfs_ready(
            runtime_wait_input(args)
        ),
    )

    runtime_wait_stopped = subparsers.add_parser(
        "macos-runtime-wait-stopped",
        help="wait until the VM lifecycle document reports stopped",
    )
    runtime_wait_stopped.add_argument("--vm-home", type=Path, required=True)
    runtime_wait_stopped.add_argument("--timeout", type=int, required=True)
    runtime_wait_stopped.set_defaults(
        handler=lambda args: macos_runtime_usecases.wait_stopped(
            runtime_wait_input(args)
        ),
    )

    runtime_health = subparsers.add_parser(
        "macos-runtime-health",
        help="check local development VM and proxy health",
    )
    runtime_health.add_argument("--vm-home", type=Path, required=True)
    runtime_health.add_argument("--proxy-port", required=True)
    runtime_health.set_defaults(
        handler=lambda args: macos_runtime_usecases.health(
            usecase_inputs.RuntimeHealthInput(
                config=args.config,
                vm_home=args.vm_home,
                proxy_port=args.proxy_port,
            )
        )
    )

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
    update_bundle.set_defaults(
        handler=lambda args: update_bundle_usecases.build_update_bundle(
            update_bundle_input(args)
        )
    )

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
    release_update_bundle.set_defaults(
        handler=lambda args: macos_update_bundle_usecases.build_update_bundle(
            release_update_bundle_input(args)
        ),
    )

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
    release_update_bundle_verify.add_argument("--output-dir", type=Path)
    release_update_bundle_verify.set_defaults(
        handler=lambda args: macos_update_bundle_usecases.verify_update_bundle(
            usecase_inputs.VerifyReleaseUpdateBundleInput(
                config=args.config,
                release_file=args.release_file,
                bundle_name=args.bundle_name,
                bundle_kind=args.bundle_kind,
                output_dir=args.output_dir,
            )
        ),
    )

    release_pkg = subparsers.add_parser(
        "release-pkg",
        help="build a macOS runtime pkg from release.json",
    )
    add_release_package_arguments(release_pkg)
    release_pkg.set_defaults(
        handler=lambda args: macos_package_usecases.build_pkg(
            release_package_input(args)
        )
    )

    release_dmg = subparsers.add_parser(
        "release-dmg",
        help="build a macOS runtime dmg from release.json",
    )
    add_release_package_arguments(release_dmg)
    release_dmg.set_defaults(
        output_kind="dmg",
        handler=lambda args: macos_package_usecases.build_dmg(
            release_package_input(args)
        ),
    )

    macos_package_clean = subparsers.add_parser(
        "macos-package-clean",
        help="remove generated macOS package artifacts",
    )
    macos_package_clean.add_argument("--release-file", type=Path, required=True)
    macos_package_clean.set_defaults(
        handler=lambda args: macos_package_usecases.clean_package(
            usecase_inputs.MacOSPackageCleanInput(
                config=args.config,
                release_file=args.release_file,
            )
        ),
    )

    macos_package_install = subparsers.add_parser(
        "macos-package-install",
        help="install the macOS runtime pkg computed from release.json",
    )
    macos_package_install.add_argument("--release-file", type=Path, required=True)
    macos_package_install.add_argument("--install-settings")
    macos_package_install.set_defaults(
        handler=lambda args: macos_package_usecases.install_pkg(
            usecase_inputs.MacOSPackageInstallInput(
                config=args.config,
                release_file=args.release_file,
                install_settings=args.install_settings,
            )
        )
    )

    verify_update_bundle = subparsers.add_parser(
        "verify-update-bundle",
        help="verify an update bundle manifest and checksums",
    )
    verify_update_bundle.add_argument("bundle_path", type=Path)
    verify_update_bundle.set_defaults(
        handler=lambda args: update_bundle_usecases.verify_update_bundle(
            usecase_inputs.VerifyUpdateBundleInput(
                bundle_path=args.bundle_path,
            )
        )
    )

    render_template = subparsers.add_parser(
        "render-template",
        help="render a small ${VAR} template",
    )
    render_template.add_argument("--template", required=True, type=Path)
    render_template.add_argument("--output", required=True, type=Path)
    render_template.add_argument("--var", action="append", default=[])
    render_template.set_defaults(
        handler=lambda args: toolchain_usecases.render_template(
            usecase_inputs.RenderTemplateInput(
                template=args.template,
                output=args.output,
                var=args.var,
            )
        )
    )

    proxy_config = subparsers.add_parser("proxy-config")
    add_proxy_arguments(proxy_config)
    proxy_config.set_defaults(
        handler=lambda args: host_proxy_usecases.render_config(proxy_input(args))
    )

    proxy_write_config = subparsers.add_parser("proxy-write-config")
    add_proxy_arguments(proxy_write_config)
    proxy_write_config.set_defaults(
        handler=lambda args: host_proxy_usecases.write_config(proxy_input(args))
    )

    proxy_test = subparsers.add_parser("proxy-test")
    add_proxy_arguments(proxy_test)
    proxy_test.set_defaults(
        handler=lambda args: host_proxy_usecases.test_config(proxy_input(args))
    )

    proxy_start = subparsers.add_parser("proxy-start")
    add_proxy_arguments(proxy_start)
    proxy_start.set_defaults(
        handler=lambda args: host_proxy_usecases.start(proxy_input(args))
    )

    proxy_port_check = subparsers.add_parser("proxy-port-check")
    add_proxy_arguments(proxy_port_check)
    proxy_port_check.set_defaults(
        handler=lambda args: host_proxy_usecases.check_port(proxy_input(args))
    )

    proxy_stop = subparsers.add_parser("proxy-stop")
    add_proxy_arguments(proxy_stop)
    proxy_stop.set_defaults(
        handler=lambda args: host_proxy_usecases.stop(proxy_input(args))
    )

    proxy_stop_orphans = subparsers.add_parser("proxy-stop-orphans")
    add_proxy_arguments(proxy_stop_orphans)
    proxy_stop_orphans.set_defaults(
        handler=lambda args: host_proxy_usecases.stop_orphans(proxy_input(args)),
    )

    proxy_clean = subparsers.add_parser("proxy-clean")
    add_proxy_arguments(proxy_clean)
    proxy_clean.set_defaults(
        handler=lambda args: host_proxy_usecases.clean(proxy_input(args))
    )

    proxy_reload = subparsers.add_parser("proxy-reload")
    add_proxy_arguments(proxy_reload)
    proxy_reload.set_defaults(
        handler=lambda args: host_proxy_usecases.reload(proxy_input(args))
    )

    proxy_status = subparsers.add_parser("proxy-status")
    add_proxy_arguments(proxy_status)
    proxy_status.set_defaults(
        handler=lambda args: host_proxy_usecases.status(proxy_input(args))
    )

    proxy_plist = subparsers.add_parser("proxy-plist")
    add_proxy_arguments(proxy_plist)
    proxy_plist.set_defaults(
        handler=lambda args: host_proxy_usecases.render_launchd_plist(
            proxy_input(args)
        )
    )

    env_bootstrap = subparsers.add_parser("env-bootstrap")
    add_environment_arguments(env_bootstrap)
    env_bootstrap.set_defaults(
        handler=lambda args: environment_usecases.bootstrap_environment(
            environment_input(args)
        )
    )

    env_doctor = subparsers.add_parser("env-doctor")
    add_environment_arguments(env_doctor)
    env_doctor.set_defaults(
        handler=lambda args: environment_usecases.diagnose_environment(
            environment_input(args)
        )
    )

    require_uv = subparsers.add_parser("require-uv")
    add_environment_arguments(require_uv)
    require_uv.set_defaults(
        handler=lambda args: environment_usecases.require_uv(
            environment_input(args)
        )
    )

    compose = subparsers.add_parser("compose")
    add_compose_arguments(compose)
    compose.add_argument("compose_args", nargs=argparse.REMAINDER)
    compose.set_defaults(
        handler=lambda args: workspace_usecases.execute_compose_command(
            usecase_inputs.ComposeCommandInput(
                compose=args.compose,
                compose_args=args.compose_args,
                bind_host=args.bind_host,
                http_port=args.http_port,
                redis_host=args.redis_host,
                redis_port=args.redis_port,
                trust_proxy=args.trust_proxy,
            )
        )
    )

    open_app = subparsers.add_parser("open")
    open_app.add_argument("--port", required=True)
    open_app.set_defaults(
        handler=lambda args: workspace_usecases.open_product_url(
            usecase_inputs.OpenProductUrlInput(port=args.port)
        )
    )

    python_tool = subparsers.add_parser("python-tool")
    python_tool.add_argument("--uv", default="uv")
    python_tool.add_argument("tool_args", nargs=argparse.REMAINDER)
    python_tool.set_defaults(
        handler=lambda args: workspace_usecases.execute_python_workspace_tool(
            usecase_inputs.PythonWorkspaceToolInput(
                uv=args.uv,
                tool_args=args.tool_args,
            )
        )
    )

    args = parser.parse_args()

    try:
        return args.handler(args)
    except DomainError as exc:
        raise SystemExit(str(exc)) from exc


def proxy_input(args: argparse.Namespace) -> usecase_inputs.HostProxyInput:
    return usecase_inputs.HostProxyInput(
        runtime_dir=args.runtime_dir,
        proxy_config=args.proxy_config,
        port=args.port,
        bind_host=args.bind_host,
        http_port=args.http_port,
        upstream=args.upstream,
        trust_proxy=args.trust_proxy,
        nginx_bin=args.nginx_bin,
        nginx_conf=args.nginx_conf,
        nginx_prefix=args.nginx_prefix,
    )


def parse_bool(value: str) -> bool:
    if value == "true":
        return True
    if value == "false":
        return False
    raise SystemExit(f"error: expected true or false, got: {value}")


def environment_input(
    args: argparse.Namespace,
) -> usecase_inputs.EnvironmentInput:
    return usecase_inputs.EnvironmentInput(
        proxy=proxy_input(args),
        python=args.python,
        uv=args.uv,
        compose=args.compose,
    )


def nginx_bundle_input(
    args: argparse.Namespace,
) -> usecase_inputs.NginxBundleInput:
    return usecase_inputs.NginxBundleInput(
        config=args.config,
        bundle_dir=args.bundle_dir,
        binary=args.binary,
        expected_version=args.expected_version,
        release_file=args.release_file,
    )


def runtime_wait_input(
    args: argparse.Namespace,
) -> usecase_inputs.RuntimeWaitInput:
    return usecase_inputs.RuntimeWaitInput(
        config=args.config,
        vm_home=args.vm_home,
        timeout=args.timeout,
    )


def macos_app_input(args: argparse.Namespace) -> usecase_inputs.MacOSAppInput:
    return usecase_inputs.MacOSAppInput(
        config=args.config,
        release_file=args.release_file,
        sdkroot=args.sdkroot,
        clang_module_cache=args.clang_module_cache,
        codesign_identity=args.codesign_identity,
    )


def update_bundle_input(
    args: argparse.Namespace,
) -> usecase_inputs.BuildUpdateBundleInput:
    return usecase_inputs.BuildUpdateBundleInput(
        version=args.version,
        runtime_version=args.runtime_version,
        bundle_name=args.bundle_name,
        channel=args.channel,
        release_label=args.release_label,
        min_updater_version=args.min_updater_version,
        bundle_kind=args.bundle_kind,
        helper_version=args.helper_version,
        target_platform=args.target_platform,
        component=args.component,
        requires_guest_activation=args.requires_guest_activation,
        requires_two_phase_update=args.requires_two_phase_update,
        output_dir=args.output_dir,
        rootfs_base=args.rootfs_base,
        app_bundle=args.app_bundle,
        runtime_tools=args.runtime_tools,
        nginx_bundle=args.nginx_bundle,
        guest_deploy=args.guest_deploy,
        migration=args.migration,
    )


def release_update_bundle_input(
    args: argparse.Namespace,
) -> usecase_inputs.ReleaseUpdateBundleInput:
    return usecase_inputs.ReleaseUpdateBundleInput(
        config=args.config,
        release_file=args.release_file,
        bundle_name=args.bundle_name,
        bundle_kind=args.bundle_kind,
        target_platform=args.target_platform,
        output_dir=args.output_dir,
        rootfs_base=args.rootfs_base,
        migration=args.migration,
        requires_two_phase_update=args.requires_two_phase_update,
        compression_threads=args.compression_threads,
        sdkroot=args.sdkroot,
        clang_module_cache=args.clang_module_cache,
        codesign_identity=args.codesign_identity,
        nginx_binary=args.nginx_binary,
        nginx_expected_version=args.nginx_expected_version,
        docker_platform=args.docker_platform,
    )


def release_package_input(
    args: argparse.Namespace,
) -> usecase_inputs.ReleasePackageInput:
    return usecase_inputs.ReleasePackageInput(
        config=args.config,
        release_file=args.release_file,
        output=args.output,
        output_kind=args.output_kind,
        rootfs_base=args.rootfs_base,
        golden_runtime_dir=args.golden_runtime_dir,
        proxy_port=args.proxy_port,
        compression_threads=args.compression_threads,
        sdkroot=args.sdkroot,
        clang_module_cache=args.clang_module_cache,
        codesign_identity=args.codesign_identity,
        nginx_binary=args.nginx_binary,
        nginx_expected_version=args.nginx_expected_version,
        docker_platform=args.docker_platform,
    )


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


def add_rootfs_base_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--force", type=parse_bool, default=False)
    parser.add_argument("--compression-threads", type=int)


def add_proxy_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--runtime-dir", default=".tmp/macos-nginx")
    parser.add_argument("--proxy-config", default=".tmp/macos-nginx/vitalserver.conf")
    parser.add_argument("--port", default="80")
    parser.add_argument("--bind-host", default="127.0.0.1")
    parser.add_argument("--http-port", default="18080")
    parser.add_argument("--upstream", default="127.0.0.1:18080")
    parser.add_argument("--trust-proxy", default="1")
    parser.add_argument("--nginx-bin", default="/opt/homebrew/bin/nginx")
    parser.add_argument(
        "--nginx-conf",
        default="/Library/Application Support/VitalServerHelper/nginx/vitalserver.conf",
    )
    parser.add_argument(
        "--nginx-prefix",
        default="/Library/Application Support/VitalServerHelper/nginx",
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
