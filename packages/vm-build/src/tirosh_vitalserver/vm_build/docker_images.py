from __future__ import annotations

from argparse import Namespace

from .compression import compression_threads, gzip_command
from .config import load_config, optional_string, required_string_list, section
from .paths import repo_root
from .process import require_tool, run


def run_docker_images(args: Namespace) -> int:
    root = repo_root()
    config = load_config(args.config)
    docker_config = section(config, "docker_images")
    bundle_path = args.bundle_path or root / optional_string(
        docker_config,
        "bundle_path",
        ".tmp/vitalserver-vm-pkg/docker-images/vitalserver-images.tar.gz",
    )
    build_platform = args.platform or optional_string(
        docker_config,
        "platform",
        "linux/amd64",
    )
    images = required_string_list(docker_config, "images")
    app_image = images[0]

    require_tool("docker")
    bundle_path.parent.mkdir(parents=True, exist_ok=True)

    print("Preparing Docker image bundle")
    print(f"VitalServer image platform: {build_platform}")
    print(f"Bundle: {bundle_path}")

    for image in images[1:]:
        run(["docker", "pull", image])

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
            str(root / "apps/vitalserver/docker/Dockerfile"),
            str(root),
        ]
    )

    threads = compression_threads(args.compression_threads)
    gzip_command(["docker", "save", *images], bundle_path, threads=threads)
    print(f"Docker image bundle is ready: {bundle_path}")
    return 0
