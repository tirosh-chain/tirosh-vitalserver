from __future__ import annotations

import hashlib
import io
import json
import tarfile
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_services import docker_images
from tirosh_vitalserver.devtools.core.guest_services import DockerImagePlan

IMAGE = "example.invalid/product:1.0.0"


def test_verify_docker_image_bundle_accepts_complete_platform_archive(
    tmp_path: Path,
) -> None:
    bundle = tmp_path / "images.tar.gz"
    write_oci_docker_archive(bundle)

    docker_images.verify_docker_image_bundle(
        bundle_path=bundle,
        expected_images=[IMAGE],
        expected_platform="linux/arm64",
    )


def test_verify_docker_image_bundle_accepts_unspecified_arm_variant(
    tmp_path: Path,
) -> None:
    bundle = tmp_path / "images.tar.gz"
    write_oci_docker_archive(bundle, variant="v8")

    docker_images.verify_docker_image_bundle(
        bundle_path=bundle,
        expected_images=[IMAGE],
        expected_platform="linux/arm64",
    )


def test_verify_docker_image_bundle_rejects_missing_manifest_blob(
    tmp_path: Path,
) -> None:
    bundle = tmp_path / "images.tar.gz"
    write_oci_docker_archive(bundle, include_config=False)

    with pytest.raises(SystemExit, match="archive member is missing"):
        docker_images.verify_docker_image_bundle(
            bundle_path=bundle,
            expected_images=[IMAGE],
            expected_platform="linux/arm64",
        )


def test_verify_docker_image_bundle_rejects_blob_digest_mismatch(
    tmp_path: Path,
) -> None:
    bundle = tmp_path / "images.tar.gz"
    write_oci_docker_archive(bundle, corrupt_layer=True)

    with pytest.raises(SystemExit, match="OCI blob digest mismatch"):
        docker_images.verify_docker_image_bundle(
            bundle_path=bundle,
            expected_images=[IMAGE],
            expected_platform="linux/arm64",
        )


def test_verify_docker_image_bundle_rejects_other_platform(tmp_path: Path) -> None:
    bundle = tmp_path / "images.tar.gz"
    write_oci_docker_archive(bundle, architecture="amd64")

    with pytest.raises(SystemExit, match="platform does not match compile plan"):
        docker_images.verify_docker_image_bundle(
            bundle_path=bundle,
            expected_images=[IMAGE],
            expected_platform="linux/arm64",
        )


def test_verify_docker_image_bundle_rejects_nested_oci_platform_mismatch(
    tmp_path: Path,
) -> None:
    bundle = tmp_path / "images.tar.gz"
    write_oci_docker_archive(bundle, nested_architecture="amd64")

    with pytest.raises(SystemExit, match="platform does not match compile plan"):
        docker_images.verify_docker_image_bundle(
            bundle_path=bundle,
            expected_images=[IMAGE],
            expected_platform="linux/arm64",
        )


def test_build_docker_image_bundle_exports_only_the_guest_platform(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    bundle = tmp_path / "images.tar.gz"
    plan = DockerImagePlan(
        build_context=tmp_path,
        platform="linux/arm64",
        images=[IMAGE],
        pull_images=[],
        app_image=IMAGE,
        app_dockerfile=tmp_path / "Dockerfile",
        recorder_ingress_image="recorder-ingress:1.0.0",
        recorder_ingress_dockerfile=tmp_path / "ingress.Dockerfile",
        recorder_recovery_image="recorder-recovery:1.0.0",
        recorder_recovery_dockerfile=tmp_path / "recovery.Dockerfile",
        vitaldb_observer_image="observer:1.0.0",
        vitaldb_observer_dockerfile=tmp_path / "observer.Dockerfile",
        redis_relay_image="relay:1.0.0",
        redis_relay_dockerfile=tmp_path / "relay.Dockerfile",
        lab_image="lab:1.0.0",
        lab_dockerfile=tmp_path / "lab.Dockerfile",
    )
    commands: list[list[str]] = []
    monkeypatch.setattr(docker_images, "require_tool", lambda _: None)
    monkeypatch.setattr(
        docker_images,
        "run_docker_build",
        lambda **_: None,
    )
    monkeypatch.setattr(
        docker_images,
        "gzip_command",
        lambda command, output, *, threads: (
            commands.append(list(command)),
            write_oci_docker_archive(output),
        ),
    )

    result = docker_images.build_docker_image_bundle(
        plan=plan,
        bundle_path=bundle,
        compression_threads_value=1,
    )

    assert result == 0
    assert commands == [
        ["docker", "image", "save", "--platform", "linux/arm64", IMAGE]
    ]


def write_oci_docker_archive(
    destination: Path,
    *,
    architecture: str = "arm64",
    variant: str | None = None,
    include_config: bool = True,
    corrupt_layer: bool = False,
    nested_architecture: str | None = None,
) -> None:
    config = b'{"architecture":"arm64","os":"linux"}'
    layer = b"layer-content"
    config_digest = sha256(config)
    layer_digest = sha256(layer)
    image_manifest = json_bytes(
        {
            "schemaVersion": 2,
            "config": {
                "mediaType": "application/vnd.oci.image.config.v1+json",
                "digest": f"sha256:{config_digest}",
                "size": len(config),
            },
            "layers": [
                {
                    "mediaType": "application/vnd.oci.image.layer.v1.tar",
                    "digest": f"sha256:{layer_digest}",
                    "size": len(layer),
                }
            ],
        }
    )
    image_manifest_digest = sha256(image_manifest)
    image_descriptor = {
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "digest": f"sha256:{image_manifest_digest}",
        "size": len(image_manifest),
        "platform": {
            "os": "linux",
            "architecture": nested_architecture or architecture,
            **({"variant": variant} if variant else {}),
        },
    }
    nested_index = None
    if nested_architecture is None:
        index = json_bytes({"schemaVersion": 2, "manifests": [image_descriptor]})
    else:
        nested_index = json_bytes({"schemaVersion": 2, "manifests": [image_descriptor]})
        nested_index_digest = sha256(nested_index)
        index = json_bytes(
            {
                "schemaVersion": 2,
                "manifests": [
                    {
                        "mediaType": "application/vnd.oci.image.index.v1+json",
                        "digest": f"sha256:{nested_index_digest}",
                        "size": len(nested_index),
                    }
                ],
            }
        )
    legacy_manifest = json_bytes(
        [
            {
                "Config": f"blobs/sha256/{config_digest}",
                "RepoTags": [IMAGE],
                "Layers": [f"blobs/sha256/{layer_digest}"],
            }
        ]
    )
    with tarfile.open(destination, "w:gz") as archive:
        add_tar_member(archive, "oci-layout", b'{"imageLayoutVersion":"1.0.0"}')
        if include_config:
            add_tar_member(archive, f"blobs/sha256/{config_digest}", config)
        add_tar_member(
            archive,
            f"blobs/sha256/{layer_digest}",
            b"corrupt-layer" if corrupt_layer else layer,
        )
        add_tar_member(
            archive,
            f"blobs/sha256/{image_manifest_digest}",
            image_manifest,
        )
        if nested_index is not None:
            add_tar_member(
                archive,
                f"blobs/sha256/{nested_index_digest}",
                nested_index,
            )
        add_tar_member(archive, "index.json", index)
        add_tar_member(archive, "manifest.json", legacy_manifest)


def add_tar_member(archive: tarfile.TarFile, name: str, content: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(content)
    archive.addfile(info, io.BytesIO(content))


def json_bytes(document: object) -> bytes:
    return json.dumps(document, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()
