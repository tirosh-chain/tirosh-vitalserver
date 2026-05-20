from __future__ import annotations

import argparse
from pathlib import Path

from .cloud_init import run_cloud_init
from .config import default_config_path, parse_bool
from .docker_images import run_docker_images
from .render_template import run_render_template
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
    update_bundle.add_argument("--runtime-pkg", type=Path)
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
