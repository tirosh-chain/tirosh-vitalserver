from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.gzip_compression import (
    compression_threads,
    gzip_command,
)
from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import (
    require_tool,
    run,
)
from tirosh_vitalserver.devtools.core.guest_services import DockerImagePlan


def build_docker_image_bundle(
    *,
    plan: DockerImagePlan,
    bundle_path: Path,
    compression_threads_value: int | None,
) -> int:
    require_tool("docker")
    bundle_path.parent.mkdir(parents=True, exist_ok=True)

    print("Preparing Docker image bundle")
    print(f"Container image platform: {plan.platform}")
    print(f"Bundle: {bundle_path}")

    for image in plan.pull_images:
        run(["docker", "pull", "--platform", plan.platform, image])

    run_docker_build(
        platform=plan.platform,
        image=plan.app_image,
        dockerfile=plan.app_dockerfile,
        context=plan.build_context,
    )
    if plan.audit_proxy_image in plan.images:
        run_docker_build(
            platform=plan.platform,
            image=plan.audit_proxy_image,
            dockerfile=plan.audit_proxy_dockerfile,
            context=plan.build_context,
        )
    if plan.vitaldb_observer_image in plan.images:
        run_docker_build(
            platform=plan.platform,
            image=plan.vitaldb_observer_image,
            dockerfile=plan.vitaldb_observer_dockerfile,
            context=plan.build_context,
        )

    threads = compression_threads(compression_threads_value)
    gzip_command(["docker", "save", *plan.images], bundle_path, threads=threads)
    print(f"Docker image bundle is ready: {bundle_path}")
    return 0


def run_docker_build(
    *,
    platform: str,
    image: str,
    dockerfile: Path,
    context: Path,
) -> None:
    run(
        [
            "docker",
            "buildx",
            "build",
            "--platform",
            platform,
            "--load",
            "-t",
            image,
            "-f",
            str(dockerfile),
            str(context),
        ]
    )
