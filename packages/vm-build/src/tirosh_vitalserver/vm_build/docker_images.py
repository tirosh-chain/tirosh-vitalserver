from __future__ import annotations

from argparse import Namespace

from .compression import compression_threads, gzip_command
from .config import (
    load_config,
    optional_string,
    required_string,
    required_string_list,
    section,
)
from .paths import repo_root
from .process import require_tool, run


def run_docker_images(args: Namespace) -> int:
    root = repo_root()
    config = load_config(args.config)
    docker_config = section(config, "docker_images")
    bundle_path = args.bundle_path or root / required_string(
        docker_config,
        "bundle_path",
    )
    build_platform = args.platform or optional_string(
        docker_config,
        "platform",
        "linux/arm64",
    )
    images = required_string_list(docker_config, "images")
    app_image = images[0]
    app_dockerfile = root / required_string(docker_config, "app_dockerfile")
    audit_proxy_image = required_string(docker_config, "audit_proxy_image")
    audit_proxy_dockerfile = root / required_string(
        docker_config,
        "audit_proxy_dockerfile",
    )
    vitaldb_observer_image = required_string(docker_config, "vitaldb_observer_image")
    vitaldb_observer_dockerfile = root / required_string(
        docker_config,
        "vitaldb_observer_dockerfile",
    )

    require_tool("docker")
    bundle_path.parent.mkdir(parents=True, exist_ok=True)

    print("Preparing Docker image bundle")
    print(f"Container image platform: {build_platform}")
    print(f"Bundle: {bundle_path}")

    for image in images[1:]:
        if image in {audit_proxy_image, vitaldb_observer_image}:
            continue
        run(["docker", "pull", "--platform", build_platform, image])

    run(
        [
            "docker",
            "buildx",
            "build",
            "--platform",
            build_platform,
            "--load",
            "-t",
            app_image,
            "-f",
            str(app_dockerfile),
            str(root),
        ]
    )
    if audit_proxy_image in images:
        run(
            [
                "docker",
                "buildx",
                "build",
                "--platform",
                build_platform,
                "--load",
                "-t",
                audit_proxy_image,
                "-f",
                str(audit_proxy_dockerfile),
                str(root),
            ]
        )
    if vitaldb_observer_image in images:
        run(
            [
                "docker",
                "buildx",
                "build",
                "--platform",
                build_platform,
                "--load",
                "-t",
                vitaldb_observer_image,
                "-f",
                str(vitaldb_observer_dockerfile),
                str(root),
            ]
        )

    threads = compression_threads(args.compression_threads)
    gzip_command(["docker", "save", *images], bundle_path, threads=threads)
    print(f"Docker image bundle is ready: {bundle_path}")
    return 0
