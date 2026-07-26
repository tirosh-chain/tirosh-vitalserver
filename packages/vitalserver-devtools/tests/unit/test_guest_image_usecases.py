from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from types import SimpleNamespace

import pytest
from pytest import MonkeyPatch

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    REQUIRED_ROOTFS_STAGES,
    ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION,
    rootfs_artifact_manifest_path,
)
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    GUEST_DEPLOY_MATERIAL_DIGEST_VERSION,
    guest_deploy_material_sha256,
)
from tirosh_vitalserver.devtools.application.inputs import (
    GuestDeploymentInput,
    UbuntuBootAssetsInput,
)
from tirosh_vitalserver.devtools.application.usecases import (
    guest_image as guest_image_usecases,
)
from tirosh_vitalserver.devtools.application.usecases import (
    guest_services as guest_services_usecases,
)
from tirosh_vitalserver.devtools.application.usecases.guest_services import (
    stage_rootfs_input_metadata,
)
from tirosh_vitalserver.devtools.config.build_toml import load_build_toml
from tirosh_vitalserver.devtools.config.guest_image import (
    load_guest_runtime_config,
    load_ubuntu_image_config,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.guest_image import (
    GuestRuntimeConfig,
    RuntimeDataDiskConfig,
    UbuntuBootAssetPlan,
    runtime_data_disk_plan,
    ubuntu_boot_asset_plan,
    ubuntu_download_cache_key,
)
from tirosh_vitalserver.devtools.core.guest_services import (
    GuestDeployPlan,
    RootfsInputMetadataPlan,
    rootfs_input_metadata_document,
)


def test_prepare_ubuntu_boot_assets_builds_plan_from_config(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    plan: UbuntuBootAssetPlan | None = None

    def load_config(path: Path) -> dict[str, dict[str, object]]:
        return {
            "guest": {
                "ubuntu": {
                    "version": "24.04",
                    "base_url": "https://example.invalid/noble",
                    "apt_snapshot": "20250313T000000Z",
                    "arch": "auto",
                    "kernel_suffix": "vmlinuz-generic",
                    "initrd_suffix": "initrd-generic",
                },
                "runtime": {
                    "runtime_dir": "runtime",
                    "rootfs_size": "8G",
                    "disk_image_name": "disk.img",
                },
                "runtime_data": {
                    "disk_image_name": "runtime-data.img",
                    "disk_size": "16G",
                    "filesystem_label": "vital-runtime",
                    "mount_path": "/mnt/runtime",
                    "docker_data_root": "/mnt/runtime/docker",
                    "containerd_root": "/mnt/runtime/containerd",
                },
            },
        }

    def run_ubuntu(value: UbuntuBootAssetPlan) -> int:
        nonlocal plan
        plan = value
        return 0

    monkeypatch.setattr(guest_image_usecases, "load_config", load_config)
    monkeypatch.setattr(
        guest_image_usecases,
        "default_runtime_dir",
        lambda: tmp_path / "default-runtime",
    )
    monkeypatch.setattr(guest_image_usecases, "host_machine", lambda: "arm64")
    monkeypatch.setattr(guest_image_usecases, "run_ubuntu", run_ubuntu)

    result = guest_image_usecases.prepare_ubuntu_boot_assets(
        UbuntuBootAssetsInput(
            config=Path("config/vm-build.toml"),
            runtime_dir=None,
            rootfs_size=None,
            recreate_rootfs=None,
            disk_image_name=None,
        )
    )

    assert result == 0
    assert plan is not None
    assert plan.arch == "arm64"
    assert plan.runtime_dir == Path("runtime")
    assert (
        plan.download_dir
        == Path("runtime")
        / "downloads"
        / ubuntu_download_cache_key("https://example.invalid/noble")
    )
    assert plan.rootfs_size == "8G"
    assert plan.disk_image_name == "disk.img"


def test_guest_runtime_config_loads_explicit_runtime_data_disk_contract() -> None:
    runtime_config = load_guest_runtime_config(
        {
            "guest": {
                "runtime": {
                    "runtime_dir": "runtime",
                    "rootfs_size": "8G",
                    "disk_image_name": "vm-disk.img",
                },
                "runtime_data": {
                    "disk_image_name": "runtime-data.img",
                    "disk_size": "16G",
                    "filesystem_label": "vital-runtime",
                    "mount_path": "/mnt/runtime",
                    "docker_data_root": "/mnt/runtime/docker",
                    "containerd_root": "/mnt/runtime/containerd",
                },
            },
        }
    )

    assert runtime_config.runtime_dir == Path("runtime")
    assert runtime_config.runtime_data_disk_image == Path("runtime/runtime-data.img")
    assert runtime_config.runtime_data_disk.disk_size == "16G"
    assert runtime_config.runtime_data_disk.filesystem_label == "vital-runtime"
    assert runtime_config.runtime_data_disk.mount_path == "/mnt/runtime"
    assert runtime_config.runtime_data_disk.docker_data_root == "/mnt/runtime/docker"
    assert runtime_config.runtime_data_disk.containerd_root == "/mnt/runtime/containerd"


def test_guest_runtime_config_requires_runtime_data_disk_contract() -> None:
    with pytest.raises(SystemExit, match=r"missing \[guest.runtime_data\]"):
        load_guest_runtime_config(
            {
                "guest": {
                    "runtime": {
                        "runtime_dir": "runtime",
                        "rootfs_size": "8G",
                        "disk_image_name": "vm-disk.img",
                    },
                },
            }
        )


def test_runtime_data_disk_plan_rejects_ext_label_too_long(tmp_path: Path) -> None:
    runtime_config = GuestRuntimeConfig(
        runtime_dir=tmp_path / "runtime",
        rootfs_size="8G",
        recreate_rootfs=False,
        disk_image_name="vm-disk.img",
        runtime_data_disk=RuntimeDataDiskConfig(
            disk_image_name="runtime-data.img",
            disk_size="16G",
            filesystem_label="vital-runtime-data",
            mount_path="/mnt/runtime",
            docker_data_root="/mnt/runtime/docker",
            containerd_root="/mnt/runtime/containerd",
        ),
    )

    with pytest.raises(DomainError, match="too long for ext filesystem label"):
        runtime_data_disk_plan(
            config_path=tmp_path / "vm-build.toml",
            vm_home=tmp_path / "vm-home",
            runtime_config=runtime_config,
        )


def test_default_ubuntu_image_config_uses_pinned_noble_release_source() -> None:
    repo_root = Path(__file__).resolve().parents[4]
    ubuntu_config = load_ubuntu_image_config(
        load_build_toml(repo_root / "config/vm-build.toml")
    )

    assert ubuntu_config.version == "24.04"
    assert ubuntu_config.base_url == (
        "https://cloud-images.ubuntu.com/releases/noble/release-20250516"
    )
    assert ubuntu_config.apt_snapshot == "20250515T000000Z"
    assert not ubuntu_config.base_url.endswith("/release")


def test_ubuntu_image_config_rejects_invalid_apt_snapshot() -> None:
    with pytest.raises(DomainError, match=r"unsupported guest\.ubuntu\.apt_snapshot"):
        load_ubuntu_image_config(
            {
                "guest": {
                    "ubuntu": {
                        "version": "24.04",
                        "base_url": "https://example.invalid/noble",
                        "apt_snapshot": "2025-03-13",
                    },
                },
            }
        )


def test_ubuntu_boot_asset_plan_rejects_rootfs_smaller_than_airgap_minimum() -> None:
    with pytest.raises(DomainError, match="rootfs_size is too small"):
        ubuntu_boot_asset_plan(
            config_path=Path("config/vm-build.toml"),
            runtime_dir=Path("runtime"),
            rootfs_size="4G",
            recreate_rootfs=True,
            disk_image_name="vm-disk.img",
            ubuntu_version="24.04",
            base_url="https://example.invalid/noble",
            requested_arch="arm64",
            host_machine="arm64",
            kernel_suffix="vmlinuz-generic",
            initrd_suffix="initrd-generic",
        )


def test_ubuntu_download_cache_key_preserves_release_source_identity() -> None:
    old_release = ubuntu_download_cache_key(
        "https://cloud-images.ubuntu.com/releases/noble/release-20250313"
    )
    new_release = ubuntu_download_cache_key(
        "https://cloud-images.ubuntu.com/releases/noble/release-20250516"
    )

    assert old_release.startswith("release-20250313-")
    assert new_release.startswith("release-20250516-")
    assert old_release != new_release


def test_stage_rootfs_input_metadata_preserves_ubuntu_source_identity(
    tmp_path: Path,
) -> None:
    base_url = "https://cloud-images.ubuntu.com/releases/noble/release-20250313"

    stage_rootfs_input_metadata(
        deploy_dir=tmp_path,
        base_url=base_url,
        apt_snapshot="20250313T000000Z",
        runtime_data=runtime_data_disk_config(),
        docker_platform="linux/arm64",
    )

    metadata = load_json(tmp_path / "build-metadata/rootfs-input.json")
    assert metadata["schemaVersion"] == 1
    assert isinstance(metadata["guestClockUtc"], str)
    assert re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
        metadata["guestClockUtc"],
    )
    assert metadata["runtimeBootSmoke"] == {"enabled": False}
    assert metadata["dockerImages"] == {"platform": "linux/arm64"}
    assert metadata["runtimeData"] == {
        "diskImageName": "runtime-data.img",
        "diskSize": "16G",
        "filesystemLabel": "vital-runtime",
        "mountPath": "/mnt/runtime",
        "dockerDataRoot": "/mnt/runtime/docker",
        "containerdRoot": "/mnt/runtime/containerd",
    }
    assert metadata["ubuntu"] == {
        "aptSnapshot": "20250313T000000Z",
        "baseUrl": base_url,
        "cacheKey": ubuntu_download_cache_key(base_url),
    }


def test_stage_rootfs_input_metadata_preserves_run_identity(
    tmp_path: Path,
) -> None:
    base_url = "https://cloud-images.ubuntu.com/releases/noble/release-20250313"

    stage_rootfs_input_metadata(
        deploy_dir=tmp_path,
        base_url=base_url,
        apt_snapshot="20250313T000000Z",
        runtime_data=runtime_data_disk_config(),
        docker_platform="linux/arm64",
        run_id="run-test",
    )

    metadata = load_json(tmp_path / "build-metadata/rootfs-input.json")
    assert metadata["runId"] == "run-test"


@pytest.mark.parametrize(
    ("staged_snapshot", "matches_receipt"),
    [
        ("20250313T000000Z", True),
        ("20260611T000000Z", False),
    ],
)
def test_stage_guest_deployment_verifies_restaged_material_against_rootfs_receipt(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    staged_snapshot: str,
    matches_receipt: bool,
) -> None:
    root = tmp_path / "repo"
    root.mkdir()
    source_deploy = tmp_path / "compiled-deploy"
    source_plan = RootfsInputMetadataPlan(
        deploy_dir=source_deploy,
        base_url="https://example.invalid/noble",
        apt_snapshot="20250313T000000Z",
        runtime_data=runtime_data_disk_config(),
        docker_platform="linux/arm64",
    )
    (source_deploy / "build-metadata").mkdir(parents=True)
    (source_deploy / "build-metadata/rootfs-input.json").write_text(
        json.dumps(rootfs_input_metadata_document(source_plan)),
        encoding="utf-8",
    )
    (source_deploy / "bootstrap.sh").write_text("#!/bin/sh\n", encoding="utf-8")
    rootfs = tmp_path / "rootfs-base.raw.gz"
    rootfs.write_bytes(b"rootfs")
    rootfs_artifact_manifest_path(rootfs).write_text(
        json.dumps(
            {
                "schemaVersion": ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION,
                "artifact": {"sha256": hashlib.sha256(b"rootfs").hexdigest()},
                "guestDeploy": {
                    "path": "data/deploy",
                    "materialDigestVersion": GUEST_DEPLOY_MATERIAL_DIGEST_VERSION,
                    "materialSha256": guest_deploy_material_sha256(source_deploy),
                },
                "source": {"runId": "rootfs-run"},
                "proof": {
                    "cleanupStatus": "passed",
                    "requiredStages": list(REQUIRED_ROOTFS_STAGES),
                },
            }
        ),
        encoding="utf-8",
    )
    vm_home = tmp_path / "runtime-smoke"
    staged_deploy = vm_home / "data/deploy"
    plan = GuestDeployPlan(
        support_guest_source=root / "Support/Guest",
        deploy_dir=staged_deploy,
        includes=[],
        python_wheel_projects=[],
        docker_bundle_source=None,
        docker_bundle_destination=None,
        optional_docker_bundle_source=None,
        optional_docker_bundle_destination=None,
        vm_data_dirs=[],
    )
    monkeypatch.setattr(guest_services_usecases, "repo_root", lambda: root)
    monkeypatch.setattr(guest_services_usecases, "load_config", lambda _: {})
    monkeypatch.setattr(
        guest_services_usecases,
        "load_guest_deploy_config",
        lambda _: object(),
    )
    monkeypatch.setattr(
        guest_services_usecases,
        "load_docker_images_config",
        lambda *_: SimpleNamespace(optional_bundle_path=None, platform="linux/arm64"),
    )
    monkeypatch.setattr(
        guest_services_usecases,
        "load_ubuntu_image_config",
        lambda _: SimpleNamespace(
            base_url="https://example.invalid/noble",
            apt_snapshot=staged_snapshot,
        ),
    )
    monkeypatch.setattr(
        guest_services_usecases,
        "load_guest_runtime_config",
        lambda _: SimpleNamespace(runtime_data_disk=runtime_data_disk_config()),
    )
    monkeypatch.setattr(guest_services_usecases, "guest_deploy_plan", lambda **_: plan)

    input = GuestDeploymentInput(
        config=root / "config.toml",
        vm_home=vm_home,
        runtime_dir=root / "runtime",
        deploy_dir=None,
        docker_bundle=None,
        rootfs_run_id=None,
        source_deploy_dir=source_deploy,
        rootfs_artifact=rootfs,
        runtime_boot_smoke_run_id="runtime-smoke-run",
    )
    if not matches_receipt:
        with pytest.raises(SystemExit, match="does not match rootfs artifact receipt"):
            guest_services_usecases.stage_guest_deployment(input)
        return

    assert guest_services_usecases.stage_guest_deployment(input) == 0
    metadata = load_json(staged_deploy / "build-metadata/rootfs-input.json")
    assert metadata["runtimeBootSmoke"] == {
        "enabled": True,
        "runId": "runtime-smoke-run",
    }


def load_json(path: Path) -> dict[str, object]:
    import json

    with path.open(encoding="utf-8") as handle:
        document = json.load(handle)
    assert isinstance(document, dict)
    return document


def runtime_data_disk_config() -> RuntimeDataDiskConfig:
    return RuntimeDataDiskConfig(
        disk_image_name="runtime-data.img",
        disk_size="16G",
        filesystem_label="vital-runtime",
        mount_path="/mnt/runtime",
        docker_data_root="/mnt/runtime/docker",
        containerd_root="/mnt/runtime/containerd",
    )
