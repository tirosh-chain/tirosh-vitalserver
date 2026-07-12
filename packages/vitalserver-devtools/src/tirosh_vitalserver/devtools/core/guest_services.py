from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.guest_deploy import GuestDeployConfig
from tirosh_vitalserver.devtools.core.guest_image import (
    RuntimeDataDiskConfig,
    ubuntu_download_cache_key,
)

VM_DATA_DIRS = ("data/deploy", "data/vital-files", "data/vr-release", "data/run")
IGNORED_NAMES = (".DS_Store", "._*", "__pycache__")
ROOTFS_INPUT_METADATA_SCHEMA_VERSION = 1


@dataclass(frozen=True)
class GuestDeployEntry:
    source: Path
    destination: Path


@dataclass(frozen=True)
class GuestPythonWheelProject:
    source: Path
    destination_directory: Path


@dataclass(frozen=True)
class GuestDeployPlan:
    support_guest_source: Path
    deploy_dir: Path
    includes: list[GuestDeployEntry]
    python_wheel_projects: list[GuestPythonWheelProject]
    docker_bundle_source: Path | None
    docker_bundle_destination: Path | None
    optional_docker_bundle_source: Path | None
    optional_docker_bundle_destination: Path | None
    vm_data_dirs: list[Path]


@dataclass(frozen=True)
class RootfsInputMetadataPlan:
    deploy_dir: Path
    base_url: str
    apt_snapshot: str
    runtime_data: RuntimeDataDiskConfig
    docker_platform: str
    run_id: str | None = None
    runtime_boot_smoke_run_id: str | None = None


@dataclass(frozen=True)
class DockerImagePlan:
    build_context: Path
    platform: str
    images: list[str]
    pull_images: list[str]
    app_image: str
    app_dockerfile: Path
    recorder_ingress_image: str
    recorder_ingress_dockerfile: Path
    recorder_recovery_image: str
    recorder_recovery_dockerfile: Path
    vitaldb_observer_image: str
    vitaldb_observer_dockerfile: Path
    redis_relay_image: str
    redis_relay_dockerfile: Path
    lab_image: str
    lab_dockerfile: Path


@dataclass(frozen=True)
class DockerImagesConfig:
    platform: str
    bundle_path: Path
    optional_bundle_path: Path | None
    images: list[str]
    optional_images: list[str]
    app_dockerfile: str
    recorder_ingress_image: str
    recorder_ingress_dockerfile: str
    recorder_recovery_image: str
    recorder_recovery_dockerfile: str
    vitaldb_observer_image: str
    vitaldb_observer_dockerfile: str
    redis_relay_image: str
    redis_relay_dockerfile: str
    lab_image: str
    lab_dockerfile: str


@dataclass(frozen=True)
class ComposeServiceImageReference:
    service: str
    image: str
    dockerfile: Path | None


def guest_deploy_plan(
    *,
    root: Path,
    runtime_dir: Path,
    deploy_dir: Path,
    vm_home: Path,
    config: GuestDeployConfig,
    docker_bundle: Path | None,
    optional_docker_bundle: Path | None = None,
    include_optional: bool = False,
) -> GuestDeployPlan:
    configured_includes = list(config.includes)
    if include_optional:
        configured_includes.extend(config.optional_includes)
    includes = [
        GuestDeployEntry(
            source=root / entry.source,
            destination=deploy_dir / entry.destination,
        )
        for entry in configured_includes
    ]
    python_wheel_projects = [
        GuestPythonWheelProject(
            source=root / project,
            destination_directory=deploy_dir / config.python_wheel_destination,
        )
        for project in config.python_wheel_projects
    ]
    docker_destination = (
        deploy_dir / config.docker_image_bundle_destination if docker_bundle else None
    )
    optional_docker_destination = (
        deploy_dir / config.optional_docker_image_bundle_destination
        if docker_bundle and config.optional_docker_image_bundle_destination
        else None
    )
    return GuestDeployPlan(
        support_guest_source=runtime_dir / "Support/Guest",
        deploy_dir=deploy_dir,
        includes=includes,
        python_wheel_projects=python_wheel_projects,
        docker_bundle_source=docker_bundle,
        docker_bundle_destination=docker_destination,
        optional_docker_bundle_source=optional_docker_bundle,
        optional_docker_bundle_destination=optional_docker_destination,
        vm_data_dirs=[vm_home / relative for relative in VM_DATA_DIRS],
    )


def rootfs_input_metadata_document(plan: RootfsInputMetadataPlan) -> dict[str, object]:
    if (
        plan.runtime_boot_smoke_run_id is not None
        and not plan.runtime_boot_smoke_run_id.strip()
    ):
        raise DomainError("runtime boot smoke runId must be non-empty when set")
    runtime_boot_smoke: dict[str, object] = {
        "enabled": plan.runtime_boot_smoke_run_id is not None,
    }
    if plan.runtime_boot_smoke_run_id is not None:
        runtime_boot_smoke["runId"] = plan.runtime_boot_smoke_run_id
    document: dict[str, object] = {
        "schemaVersion": ROOTFS_INPUT_METADATA_SCHEMA_VERSION,
        "guestClockUtc": datetime.now(UTC).replace(microsecond=0).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "runtimeBootSmoke": runtime_boot_smoke,
        "dockerImages": {
            "platform": plan.docker_platform,
        },
        "runtimeData": {
            "diskImageName": plan.runtime_data.disk_image_name,
            "diskSize": plan.runtime_data.disk_size,
            "filesystemLabel": plan.runtime_data.filesystem_label,
            "mountPath": plan.runtime_data.mount_path,
            "dockerDataRoot": plan.runtime_data.docker_data_root,
            "containerdRoot": plan.runtime_data.containerd_root,
        },
        "ubuntu": {
            "aptSnapshot": plan.apt_snapshot,
            "baseUrl": plan.base_url,
            "cacheKey": ubuntu_download_cache_key(plan.base_url),
        },
    }
    if plan.run_id:
        document["runId"] = plan.run_id
    return document


def rootfs_input_material_document(document: dict[str, object]) -> dict[str, object]:
    """Extract the stable rootfs compile contract from run-scoped metadata.

    Guest clock, proof run IDs, and runtime-smoke controls are Host-owned values
    written for an individual run. They must not change the identity of the
    Guest material compiled into a rootfs. All other rootfs inputs stay explicit.
    """

    material = {
        key: value
        for key, value in document.items()
        if key not in {"guestClockUtc", "runId", "runtimeBootSmoke"}
    }
    schema_version = material.get("schemaVersion")
    if schema_version != ROOTFS_INPUT_METADATA_SCHEMA_VERSION:
        raise DomainError(
            "rootfs input metadata schema is unsupported for material identity: "
            f"expected={ROOTFS_INPUT_METADATA_SCHEMA_VERSION} "
            f"actual={schema_version}"
        )
    docker_images = required_rootfs_material_object(material, "dockerImages")
    runtime_data = required_rootfs_material_object(material, "runtimeData")
    ubuntu = required_rootfs_material_object(material, "ubuntu")
    required_rootfs_material_string(docker_images, "dockerImages.platform")
    for field in (
        "diskImageName",
        "diskSize",
        "filesystemLabel",
        "mountPath",
        "dockerDataRoot",
        "containerdRoot",
    ):
        required_rootfs_material_string(runtime_data, f"runtimeData.{field}")
    for field in ("baseUrl", "aptSnapshot", "cacheKey"):
        required_rootfs_material_string(ubuntu, f"ubuntu.{field}")
    return material


def required_rootfs_material_object(
    document: dict[str, object],
    field: str,
) -> dict[str, object]:
    value = document.get(field)
    if not isinstance(value, dict):
        raise DomainError(
            f"rootfs input metadata is missing {field} material contract"
        )
    return value


def required_rootfs_material_string(
    document: dict[str, object],
    field: str,
) -> str:
    key = field.rsplit(".", maxsplit=1)[-1]
    value = document.get(key)
    if not isinstance(value, str) or not value.strip():
        raise DomainError(f"rootfs input metadata has invalid {field}")
    return value


def docker_image_plan(
    *,
    root: Path,
    platform: str,
    images: list[str],
    app_dockerfile: str,
    recorder_ingress_image: str,
    recorder_ingress_dockerfile: str,
    recorder_recovery_image: str,
    recorder_recovery_dockerfile: str,
    vitaldb_observer_image: str,
    vitaldb_observer_dockerfile: str,
    redis_relay_image: str,
    redis_relay_dockerfile: str,
    lab_image: str,
    lab_dockerfile: str,
) -> DockerImagePlan:
    if not images:
        raise DomainError("error: guest.docker_images.images must not be empty")
    app_image = images[0]
    local_build_images = {
        recorder_ingress_image,
        recorder_recovery_image,
        vitaldb_observer_image,
        redis_relay_image,
        lab_image,
    }
    return DockerImagePlan(
        build_context=root,
        platform=platform,
        images=images,
        pull_images=[image for image in images[1:] if image not in local_build_images],
        app_image=app_image,
        app_dockerfile=root / app_dockerfile,
        recorder_ingress_image=recorder_ingress_image,
        recorder_ingress_dockerfile=root / recorder_ingress_dockerfile,
        recorder_recovery_image=recorder_recovery_image,
        recorder_recovery_dockerfile=root / recorder_recovery_dockerfile,
        vitaldb_observer_image=vitaldb_observer_image,
        vitaldb_observer_dockerfile=root / vitaldb_observer_dockerfile,
        redis_relay_image=redis_relay_image,
        redis_relay_dockerfile=root / redis_relay_dockerfile,
        lab_image=lab_image,
        lab_dockerfile=root / lab_dockerfile,
    )


def compose_service_image_references(
    compose_text: str,
) -> tuple[ComposeServiceImageReference, ...]:
    references: list[ComposeServiceImageReference] = []
    in_services = False
    current_service: str | None = None
    current_image: str | None = None
    current_dockerfile: Path | None = None
    in_build = False

    def flush_current() -> None:
        if current_service is None or current_image is None:
            return
        references.append(
            ComposeServiceImageReference(
                service=current_service,
                image=current_image,
                dockerfile=current_dockerfile,
            )
        )

    for line in compose_text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if indent == 0:
            flush_current()
            current_service = None
            current_image = None
            current_dockerfile = None
            in_build = False
            in_services = stripped == "services:"
            continue
        if not in_services:
            continue
        if indent == 2 and stripped.endswith(":"):
            flush_current()
            current_service = stripped[:-1]
            current_image = None
            current_dockerfile = None
            in_build = False
            continue
        if current_service is None:
            continue
        if indent == 4:
            in_build = stripped == "build:"
            if stripped.startswith("image:"):
                current_image = _compose_scalar_value(stripped)
            continue
        if in_build and indent == 6 and stripped.startswith("dockerfile:"):
            current_dockerfile = Path(_compose_scalar_value(stripped))

    flush_current()
    return tuple(references)


REQUIRED_RUNTIME_PRODUCT_COMPOSE_SERVICES = frozenset(
    {
        "postgres",
        "redis",
        "app",
        "recorder-recovery",
        "recorder-ingress",
        "vitaldb-observer",
        "redis-relay",
        "lab",
        "edge",
    }
)


def guest_compose_contract_errors(
    *,
    root: Path,
    compose_text: str,
    image_plan: DockerImagePlan,
    known_images: set[str],
    deploy_include_sources: list[Path],
    optional_images: set[str] | None = None,
    include_optional: bool = False,
) -> tuple[str, ...]:
    """Return explicit product-contract errors for Guest Docker compilation.

    The function is deliberately pure: callers provide the compose text and all
    configured paths.  It identifies the exact material that must be present in
    the air-gapped Guest deploy; it neither reads the worktree nor invokes
    Docker.
    """

    references = compose_service_image_references(compose_text)
    if optional_images and not include_optional:
        references = tuple(
            reference
            for reference in references
            if reference.image not in optional_images
        )
    if not references:
        return ("Guest compose does not declare any service images",)

    errors: list[str] = []
    services = {reference.service for reference in references}
    missing_services = sorted(REQUIRED_RUNTIME_PRODUCT_COMPOSE_SERVICES - services)
    forbidden_services = sorted(service for service in services if service == "testkit")
    if missing_services or forbidden_services:
        errors.append(
            "Guest compose does not match the Runtime v2 product stack: "
            f"missing={missing_services} forbidden={forbidden_services}"
        )

    dockerfiles_by_image = _dockerfiles_by_image(image_plan)
    for reference in references:
        if reference.image not in known_images:
            errors.append(
                "Guest compose image is not declared in VM Docker image config: "
                f"service={reference.service} image={reference.image}"
            )
        if reference.dockerfile is None:
            continue
        configured = dockerfiles_by_image.get(reference.image)
        if configured is None:
            errors.append(
                "Guest compose build image has no configured Dockerfile: "
                f"service={reference.service} image={reference.image}"
            )
        else:
            try:
                configured_relative = configured.relative_to(root)
            except ValueError:
                errors.append(
                    "VM Docker image config Dockerfile is outside the workspace: "
                    f"service={reference.service} dockerfile={configured}"
                )
            else:
                if reference.dockerfile != configured_relative:
                    errors.append(
                        "Guest compose Dockerfile does not match VM Docker image "
                        "config: "
                        f"service={reference.service} "
                        f"compose={reference.dockerfile} "
                        f"config={configured_relative}"
                    )
        if not _path_is_covered_by_include(
            reference.dockerfile,
            deploy_include_sources,
        ):
            errors.append(
                "Guest compose Dockerfile is not covered by Guest deploy includes: "
                f"service={reference.service} dockerfile={reference.dockerfile}"
            )
    return tuple(errors)


def _dockerfiles_by_image(plan: DockerImagePlan) -> dict[str, Path]:
    return {
        plan.app_image: plan.app_dockerfile,
        plan.recorder_ingress_image: plan.recorder_ingress_dockerfile,
        plan.recorder_recovery_image: plan.recorder_recovery_dockerfile,
        plan.vitaldb_observer_image: plan.vitaldb_observer_dockerfile,
        plan.redis_relay_image: plan.redis_relay_dockerfile,
        plan.lab_image: plan.lab_dockerfile,
    }


def _path_is_covered_by_include(
    path: Path,
    include_sources: list[Path],
) -> bool:
    return any(
        path == source or path.is_relative_to(source)
        for source in include_sources
    )


def _compose_scalar_value(stripped_line: str) -> str:
    value = stripped_line.split(":", 1)[1].strip()
    if (
        len(value) >= 2
        and value[0] == value[-1]
        and value[0] in {'"', "'"}
    ):
        return value[1:-1]
    return value
