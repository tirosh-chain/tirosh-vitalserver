from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.vm_build.config.build_config import (
    default_config_path,
    parse_bool,
)
from tirosh_vitalserver.vm_build.guest_image.cloud_init import run_cloud_init
from tirosh_vitalserver.vm_build.guest_image.rootfs_base import (
    add_rootfs_base_arguments,
    run_rootfs_base,
)
from tirosh_vitalserver.vm_build.guest_image.ubuntu import run_ubuntu
from tirosh_vitalserver.vm_build.guest_services.docker_images import run_docker_images
from tirosh_vitalserver.vm_build.host_proxy.nginx_bundle import run_nginx_bundle
from tirosh_vitalserver.vm_build.release import (
    run_release_dmg,
    run_release_pkg,
    run_release_update_bundle,
)
from tirosh_vitalserver.vm_build.toolchain.token_template import run_render_template
from tirosh_vitalserver.vm_build.update_bundle import (
    run_build_update_bundle,
    run_verify_update_bundle,
)


def main() -> int:
    parser = argparse.ArgumentParser(prog="vitalserver-vm-build")
    parser.add_argument(
        "--config",
        type=Path,
        default=default_config_path(),
        help="build config TOML path",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

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
    release_update_bundle.add_argument("--output-dir", type=Path, required=True)
    release_update_bundle.add_argument("--rootfs-base", type=Path)
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
    args = parser.parse_args()

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
    if args.command == "update-bundle":
        return run_build_update_bundle(args)
    if args.command == "release-update-bundle":
        return run_release_update_bundle(args)
    if args.command == "release-pkg":
        return run_release_pkg(args)
    if args.command == "release-dmg":
        return run_release_dmg(args)
    if args.command == "verify-update-bundle":
        return run_verify_update_bundle(args)
    if args.command == "render-template":
        return run_render_template(args)
    parser.error(f"unsupported command: {args.command}")
    return 2


def add_release_package_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--release-file", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
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
