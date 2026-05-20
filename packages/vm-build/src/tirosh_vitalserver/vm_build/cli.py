from __future__ import annotations

import argparse
from pathlib import Path

from .cloud_init import run_cloud_init
from .config import default_config_path, parse_bool
from .docker_images import run_docker_images
from .nginx_bundle import run_nginx_bundle
from .render_template import run_render_template
from .rootfs_base import add_rootfs_base_arguments, run_rootfs_base
from .ubuntu import run_ubuntu
from .update_bundle import run_build_update_bundle, run_verify_update_bundle


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
    update_bundle.add_argument("--runtime-version", required=True)
    update_bundle.add_argument("--output-dir", type=Path, required=True)
    update_bundle.add_argument("--rootfs-base", type=Path, required=True)
    update_bundle.add_argument("--app-bundle", type=Path)
    update_bundle.add_argument("--runtime-tools", type=Path)
    update_bundle.add_argument("--nginx-bundle", type=Path)
    update_bundle.add_argument("--guest-deploy", type=Path)
    update_bundle.add_argument("--migration", action="append", type=Path, default=[])

    verify_update_bundle = subparsers.add_parser(
        "verify-update-bundle",
        help="verify an update bundle manifest and checksums",
    )
    verify_update_bundle.add_argument("bundle_dir", type=Path)

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
    if args.command == "verify-update-bundle":
        return run_verify_update_bundle(args)
    if args.command == "render-template":
        return run_render_template(args)
    parser.error(f"unsupported command: {args.command}")
    return 2
