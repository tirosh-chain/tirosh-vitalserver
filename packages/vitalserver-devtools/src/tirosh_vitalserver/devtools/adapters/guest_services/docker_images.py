from __future__ import annotations

import hashlib
import json
import tarfile
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any, NoReturn

from tirosh_vitalserver.devtools.adapters.toolchain.gzip_compression import (
    compression_threads,
    gzip_command,
)
from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import (
    require_tool,
    run,
)
from tirosh_vitalserver.devtools.core.guest_services import DockerImagePlan

OCI_JSON_BLOB_MAX_BYTES = 1024 * 1024


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
    if plan.recorder_ingress_image in plan.images:
        run_docker_build(
            platform=plan.platform,
            image=plan.recorder_ingress_image,
            dockerfile=plan.recorder_ingress_dockerfile,
            context=plan.build_context,
        )
    if plan.recorder_recovery_image in plan.images:
        run_docker_build(
            platform=plan.platform,
            image=plan.recorder_recovery_image,
            dockerfile=plan.recorder_recovery_dockerfile,
            context=plan.build_context,
        )
    if plan.vitaldb_observer_image in plan.images:
        run_docker_build(
            platform=plan.platform,
            image=plan.vitaldb_observer_image,
            dockerfile=plan.vitaldb_observer_dockerfile,
            context=plan.build_context,
        )
    if plan.redis_relay_image in plan.images:
        run_docker_build(
            platform=plan.platform,
            image=plan.redis_relay_image,
            dockerfile=plan.redis_relay_dockerfile,
            context=plan.build_context,
        )
    if plan.lab_image in plan.images:
        run_docker_build(
            platform=plan.platform,
            image=plan.lab_image,
            dockerfile=plan.lab_dockerfile,
            context=plan.build_context,
        )

    threads = compression_threads(compression_threads_value)
    gzip_command(
        ["docker", "image", "save", "--platform", plan.platform, *plan.images],
        bundle_path,
        threads=threads,
    )
    verify_docker_image_bundle(
        bundle_path=bundle_path,
        expected_images=plan.images,
        expected_platform=plan.platform,
    )
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


def verify_docker_image_bundle(
    *,
    bundle_path: Path,
    expected_images: Iterable[str],
    expected_platform: str,
) -> None:
    """Verify the Docker export before it becomes Guest compile material.

    Docker's gzip stream can be structurally valid while an OCI index or legacy
    manifest refers to blobs that were not exported.  The Guest must never be
    the first consumer to discover that defect.
    """

    expected_tags = frozenset(expected_images)
    if not expected_tags:
        fail_bundle_verification(bundle_path, "expected image set is empty")
    platform = parse_platform(expected_platform, bundle_path)
    try:
        archive = read_docker_archive(bundle_path)
    except (OSError, tarfile.TarError) as error:
        fail_bundle_verification(bundle_path, f"archive is unreadable: {error}")

    verify_legacy_manifest(
        bundle_path=bundle_path,
        archive=archive,
        expected_tags=expected_tags,
        expected_platform=platform,
    )
    if "index.json" in archive.documents or "oci-layout" in archive.members:
        verify_oci_layout(
            bundle_path=bundle_path,
            archive=archive,
            expected_platform=platform,
        )


class DockerArchive:
    def __init__(
        self,
        *,
        members: Mapping[str, int],
        blob_hashes: Mapping[str, str],
        documents: Mapping[str, bytes],
    ) -> None:
        self.members = members
        self.blob_hashes = blob_hashes
        self.documents = documents


def read_docker_archive(bundle_path: Path) -> DockerArchive:
    if not bundle_path.is_file():
        fail_bundle_verification(bundle_path, "archive is missing")
    members: dict[str, int] = {}
    blob_hashes: dict[str, str] = {}
    documents: dict[str, bytes] = {}
    with tarfile.open(bundle_path, "r:gz") as archive:
        for member in archive:
            if member.name in members:
                fail_bundle_verification(
                    bundle_path,
                    f"archive contains duplicate member: {member.name}",
                )
            members[member.name] = member.size
            if not member.isfile():
                continue
            file_object = archive.extractfile(member)
            if file_object is None:
                fail_bundle_verification(
                    bundle_path,
                    f"archive member is unreadable: {member.name}",
                )
            with file_object:
                if is_oci_blob(member.name):
                    if member.size <= OCI_JSON_BLOB_MAX_BYTES:
                        content = file_object.read()
                        blob_hashes[member.name] = hashlib.sha256(content).hexdigest()
                        documents[member.name] = content
                    else:
                        blob_hashes[member.name] = sha256_stream(file_object)
                elif member.name in {"index.json", "manifest.json"}:
                    documents[member.name] = file_object.read()
    return DockerArchive(
        members=members,
        blob_hashes=blob_hashes,
        documents=documents,
    )


def verify_legacy_manifest(
    *,
    bundle_path: Path,
    archive: DockerArchive,
    expected_tags: frozenset[str],
    expected_platform: tuple[str, str, str | None],
) -> None:
    manifest = required_json_document(
        bundle_path=bundle_path,
        archive=archive,
        name="manifest.json",
    )
    if not isinstance(manifest, list) or not manifest:
        fail_bundle_verification(bundle_path, "manifest.json must be a non-empty array")

    exported_tags: set[str] = set()
    for index, entry in enumerate(manifest):
        location = f"manifest.json[{index}]"
        if not isinstance(entry, dict):
            fail_bundle_verification(bundle_path, f"{location} must be an object")
        tags = required_string_list(bundle_path, entry, "RepoTags", location)
        for tag in tags:
            if tag in exported_tags:
                fail_bundle_verification(
                    bundle_path,
                    f"manifest.json exports duplicate image tag: {tag}",
                )
            exported_tags.add(tag)
        config = required_string(bundle_path, entry, "Config", location)
        require_archive_member(
            bundle_path,
            archive,
            config,
            location,
        )
        verify_legacy_config_platform(
            bundle_path=bundle_path,
            archive=archive,
            config_member=config,
            image_tags=tags,
            expected_platform=expected_platform,
        )
        for layer in required_string_list(bundle_path, entry, "Layers", location):
            require_archive_member(bundle_path, archive, layer, location)

    missing_tags = sorted(expected_tags - exported_tags)
    unexpected_tags = sorted(exported_tags - expected_tags)
    if missing_tags or unexpected_tags:
        fail_bundle_verification(
            bundle_path,
            "manifest image tags do not match compile plan: "
            f"missing={missing_tags} unexpected={unexpected_tags}",
        )


def verify_oci_layout(
    *,
    bundle_path: Path,
    archive: DockerArchive,
    expected_platform: tuple[str, str, str | None],
) -> None:
    if "oci-layout" not in archive.members:
        fail_bundle_verification(bundle_path, "OCI index exists without oci-layout")
    index = required_json_document(
        bundle_path=bundle_path,
        archive=archive,
        name="index.json",
    )
    if not isinstance(index, dict):
        fail_bundle_verification(bundle_path, "index.json must be an object")
    descriptors = index.get("manifests")
    if not isinstance(descriptors, list) or not descriptors:
        fail_bundle_verification(bundle_path, "index.json manifests must be non-empty")

    visited: set[str] = set()
    for index_value, descriptor in enumerate(descriptors):
        location = f"index.json.manifests[{index_value}]"
        verify_oci_descriptor(
            bundle_path=bundle_path,
            archive=archive,
            descriptor=descriptor,
            location=location,
            visited=visited,
            expected_platform=expected_platform,
        )


def verify_oci_descriptor(
    *,
    bundle_path: Path,
    archive: DockerArchive,
    descriptor: object,
    location: str,
    visited: set[str],
    expected_platform: tuple[str, str, str | None],
) -> None:
    if not isinstance(descriptor, dict):
        fail_bundle_verification(bundle_path, f"{location} must be an object")
    if descriptor.get("platform") is not None:
        actual_platform = descriptor_platform(bundle_path, descriptor, location)
        if not platform_matches(expected_platform, actual_platform):
            fail_bundle_verification(
                bundle_path,
                "OCI descriptor platform does not match compile plan: "
                f"location={location} "
                f"expected={format_platform(expected_platform)} "
                f"actual={format_platform(actual_platform)}",
            )
    digest = required_string(bundle_path, descriptor, "digest", location)
    member_name = oci_blob_member_name(bundle_path, digest, location)
    if digest in visited:
        return
    visited.add(digest)
    require_archive_member(bundle_path, archive, member_name, location)
    expected_size = descriptor.get("size")
    if not isinstance(expected_size, int) or expected_size < 0:
        fail_bundle_verification(
            bundle_path,
            f"{location}.size must be a non-negative integer",
        )
    actual_size = archive.members[member_name]
    if actual_size != expected_size:
        fail_bundle_verification(
            bundle_path,
            f"OCI descriptor size mismatch: location={location} "
            f"expected={expected_size} actual={actual_size}",
        )
    actual_digest = archive.blob_hashes.get(member_name)
    expected_hash = digest.removeprefix("sha256:")
    if actual_digest != expected_hash:
        fail_bundle_verification(
            bundle_path,
            f"OCI blob digest mismatch: location={location} "
            f"expected={digest} actual=sha256:{actual_digest or 'missing'}",
        )
    media_type = required_string(bundle_path, descriptor, "mediaType", location)
    if not is_oci_graph_document_media_type(media_type):
        return
    document = parse_json_bytes(
        bundle_path,
        archive.documents.get(member_name),
        f"OCI descriptor {digest}",
    )
    if not isinstance(document, dict):
        return
    if is_image_index_media_type(media_type):
        nested_descriptors = document.get("manifests")
        if not isinstance(nested_descriptors, list):
            fail_bundle_verification(
                bundle_path,
                f"{location}.manifests must be an array",
            )
        for nested_index, nested_descriptor in enumerate(nested_descriptors):
            verify_oci_descriptor(
                bundle_path=bundle_path,
                archive=archive,
                descriptor=nested_descriptor,
                location=f"{location}.manifests[{nested_index}]",
                visited=visited,
                expected_platform=expected_platform,
            )
        return
    if not is_image_manifest_media_type(media_type):
        return
    config = document.get("config")
    verify_oci_descriptor(
        bundle_path=bundle_path,
        archive=archive,
        descriptor=config,
        location=f"{location}.config",
        visited=visited,
        expected_platform=expected_platform,
    )
    layers = document.get("layers")
    if not isinstance(layers, list):
        fail_bundle_verification(bundle_path, f"{location}.layers must be an array")
    for layer_index, layer in enumerate(layers):
        verify_oci_descriptor(
            bundle_path=bundle_path,
            archive=archive,
            descriptor=layer,
            location=f"{location}.layers[{layer_index}]",
            visited=visited,
            expected_platform=expected_platform,
        )


def descriptor_platform(
    bundle_path: Path,
    descriptor: object,
    location: str,
) -> tuple[str, str, str | None]:
    if not isinstance(descriptor, dict):
        fail_bundle_verification(bundle_path, f"{location} must be an object")
    platform = descriptor.get("platform")
    if not isinstance(platform, dict):
        fail_bundle_verification(bundle_path, f"{location}.platform must be an object")
    operating_system = required_string(
        bundle_path,
        platform,
        "os",
        f"{location}.platform",
    )
    architecture = required_string(
        bundle_path,
        platform,
        "architecture",
        f"{location}.platform",
    )
    variant = platform.get("variant")
    if variant is not None and (not isinstance(variant, str) or not variant.strip()):
        fail_bundle_verification(
            bundle_path,
            f"{location}.platform.variant must be a non-empty string when present",
        )
    return operating_system, architecture, variant


def verify_legacy_config_platform(
    *,
    bundle_path: Path,
    archive: DockerArchive,
    config_member: str,
    image_tags: list[str],
    expected_platform: tuple[str, str, str | None],
) -> None:
    document = parse_json_bytes(
        bundle_path,
        archive.documents.get(config_member),
        f"legacy config {config_member}",
    )
    if not isinstance(document, dict):
        fail_bundle_verification(
            bundle_path,
            f"legacy config must be an object: {config_member}",
        )
    actual = (
        required_string(bundle_path, document, "os", config_member),
        required_string(bundle_path, document, "architecture", config_member),
        None,
    )
    if not platform_matches(expected_platform, actual):
        fail_bundle_verification(
            bundle_path,
            "legacy image config platform does not match compile plan: "
            f"images={image_tags} expected={format_platform(expected_platform)} "
            f"actual={format_platform(actual)}",
        )


def parse_platform(
    value: str,
    bundle_path: Path,
) -> tuple[str, str, str | None]:
    pieces = value.split("/")
    if len(pieces) not in {2, 3} or any(not piece for piece in pieces):
        fail_bundle_verification(
            bundle_path,
            "compile platform is invalid: "
            f"{value!r}; expected os/architecture[/variant]",
        )
    return pieces[0], pieces[1], pieces[2] if len(pieces) == 3 else None


def format_platform(platform: tuple[str, str, str | None]) -> str:
    operating_system, architecture, variant = platform
    return "/".join(
        value for value in (operating_system, architecture, variant) if value
    )


def platform_matches(
    expected: tuple[str, str, str | None],
    actual: tuple[str, str, str | None],
) -> bool:
    expected_os, expected_architecture, expected_variant = expected
    actual_os, actual_architecture, actual_variant = actual
    return (
        expected_os == actual_os
        and expected_architecture == actual_architecture
        and (expected_variant is None or expected_variant == actual_variant)
    )


def required_json_document(
    *,
    bundle_path: Path,
    archive: DockerArchive,
    name: str,
) -> Any:
    return parse_json_bytes(bundle_path, archive.documents.get(name), name)


def parse_json_bytes(bundle_path: Path, content: bytes | None, location: str) -> Any:
    if content is None:
        fail_bundle_verification(bundle_path, f"archive is missing {location}")
    try:
        return json.loads(content)
    except (TypeError, json.JSONDecodeError) as error:
        fail_bundle_verification(bundle_path, f"{location} is invalid JSON: {error}")


def required_string(
    bundle_path: Path,
    document: Mapping[str, object],
    key: str,
    location: str,
) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value.strip():
        fail_bundle_verification(
            bundle_path,
            f"{location}.{key} must be a non-empty string",
        )
    return value


def required_string_list(
    bundle_path: Path,
    document: Mapping[str, object],
    key: str,
    location: str,
) -> list[str]:
    value = document.get(key)
    if not isinstance(value, list) or not value:
        fail_bundle_verification(
            bundle_path,
            f"{location}.{key} must be a non-empty array",
        )
    if any(not isinstance(item, str) or not item.strip() for item in value):
        fail_bundle_verification(
            bundle_path,
            f"{location}.{key} must contain non-empty strings only",
        )
    return list(value)


def require_archive_member(
    bundle_path: Path,
    archive: DockerArchive,
    name: str,
    location: str,
) -> None:
    if name not in archive.members:
        fail_bundle_verification(
            bundle_path,
            f"archive member is missing: location={location} member={name}",
        )
    if is_oci_blob(name):
        expected_hash = name.removeprefix("blobs/sha256/")
        actual_hash = archive.blob_hashes.get(name)
        if actual_hash != expected_hash:
            fail_bundle_verification(
                bundle_path,
                f"OCI blob digest mismatch: location={location} "
                "expected=sha256:"
                f"{expected_hash} actual=sha256:{actual_hash or 'missing'}",
            )


def oci_blob_member_name(bundle_path: Path, digest: str, location: str) -> str:
    prefix = "sha256:"
    encoded = digest.removeprefix(prefix)
    if (
        not digest.startswith(prefix)
        or len(encoded) != 64
        or any(character not in "0123456789abcdef" for character in encoded)
    ):
        fail_bundle_verification(
            bundle_path,
            f"{location}.digest must be a sha256 digest: {digest!r}",
        )
    return f"blobs/sha256/{encoded}"


def is_oci_blob(name: str) -> bool:
    return name.startswith("blobs/sha256/")


def is_image_index_media_type(media_type: str) -> bool:
    return media_type in {
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
    }


def is_image_manifest_media_type(media_type: str) -> bool:
    return media_type in {
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    }


def is_image_config_media_type(media_type: str) -> bool:
    return media_type in {
        "application/vnd.oci.image.config.v1+json",
        "application/vnd.docker.container.image.v1+json",
    }


def is_oci_graph_document_media_type(media_type: str) -> bool:
    return (
        is_image_index_media_type(media_type)
        or is_image_manifest_media_type(media_type)
        or is_image_config_media_type(media_type)
    )


def sha256_stream(file_object: Any) -> str:
    digest = hashlib.sha256()
    for chunk in iter(lambda: file_object.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def fail_bundle_verification(bundle_path: Path, reason: str) -> NoReturn:
    raise SystemExit(
        "error: Docker image bundle verification failed: "
        f"bundle={bundle_path} reason={reason}"
    )
