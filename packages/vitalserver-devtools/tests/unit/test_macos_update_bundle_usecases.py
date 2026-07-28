from __future__ import annotations

import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest
from pytest import MonkeyPatch

from tirosh_vitalserver.devtools.application.inputs import (
    ApplySmokeReleaseUpdateBundleInput,
    ReleaseUpdateBundleInput,
    VerifyReleaseUpdateBundleInput,
)
from tirosh_vitalserver.devtools.application.usecases import (
    macos_update_bundle as macos_update_bundle_usecases,
)
from tirosh_vitalserver.devtools.core.release_manifest import ReleaseManifest
from tirosh_vitalserver.devtools.core.update_bundle_models import (
    BuildUpdateBundleInput,
)


@pytest.mark.parametrize(
    ("bundle_kind", "rootfs_base", "requires_two_phase_update"),
    [
        ("vm-image-update", "rootfs-base.raw.gz", False),
        ("product-update", None, True),
    ],
)
def test_release_update_bundle_forwards_explicit_updater_bridge_contract(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
    bundle_kind: str,
    rootfs_base: str | None,
    requires_two_phase_update: bool,
) -> None:
    settings = SimpleNamespace(
        runtime_dir=tmp_path / "runtime",
        clang_module_cache=tmp_path / "clang-module-cache",
        helper_product_name="VitalServerHelper",
        runtime_cli=tmp_path / "bin/vitalserver-vm",
        helper_bin=tmp_path / "bin/VitalServerHelper",
        app_bundle=tmp_path / "VitalServer Helper.app",
        app_name="VitalServer Helper",
        nginx_bundle=tmp_path / "nginx-bundle",
        docker_bundle=tmp_path / "docker-images.tar",
        update_artifact_dir=tmp_path / "update-artifacts",
        guest_deploy=SimpleNamespace(),
        dist_dir=tmp_path / "dist",
    )
    release = ReleaseManifest(
        channel="dev",
        helper_version="1.2.3",
        release_label="1.2.3-dev",
        vitalserver_version="2.3.4",
        target_platform="macos-arm64",
    )
    staged = SimpleNamespace(
        app_bundle=tmp_path / "staged/app-bundle.tar.gz",
        runtime_tools=tmp_path / "staged/runtime-tools.tar.gz",
        nginx_bundle=tmp_path / "staged/nginx-bundle.tar.gz",
        guest_deploy=tmp_path / "staged/guest-deploy.tar.gz",
    )
    captured_specs: list[BuildUpdateBundleInput] = []

    monkeypatch.setattr(macos_update_bundle_usecases, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_macos_release_settings",
        lambda config, root: settings,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_release_manifest",
        lambda path: release,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "resolve_path",
        lambda root, value: Path(value) if Path(value).is_absolute() else root / value,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "sync_release",
        lambda *args: None,
    )
    monkeypatch.setattr(macos_update_bundle_usecases, "build_swift", lambda *args: None)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "sign_runtime_cli",
        lambda *args: None,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "build_app_bundle",
        lambda **kwargs: None,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "build_nginx_bundle",
        lambda input: None,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "build_configured_docker_image_bundles",
        lambda **kwargs: None,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "guest_deploy_plan",
        lambda **kwargs: SimpleNamespace(),
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "stage_update_artifacts",
        lambda **kwargs: staged,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "build_bundle",
        captured_specs.append,
    )

    macos_update_bundle_usecases.build_update_bundle(
        ReleaseUpdateBundleInput(
            config=Path("config/vm-build.toml"),
            release_file=Path("release-dev.json"),
            bundle_name=None,
            bundle_kind=bundle_kind,
            target_platform=None,
            output_dir=Path("dist/update-bundles"),
            rootfs_base=rootfs_base,
            migration=[Path("migration")],
            requires_two_phase_update=requires_two_phase_update,
            compression_threads=None,
            sdkroot=None,
            clang_module_cache=None,
            codesign_identity="-",
            nginx_binary=None,
            nginx_expected_version="nginx/1.31.1",
            docker_platform=None,
        )
    )

    assert len(captured_specs) == 1
    captured_spec = captured_specs[0]
    assert captured_spec.bundle_kind == bundle_kind
    assert captured_spec.requires_two_phase_update is requires_two_phase_update
    assert captured_spec.min_updater_version == "0.0.0"


def test_verify_release_update_bundle_uses_explicit_output_dir(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    verified_path: Path | None = None

    def load_release_manifest(path: Path) -> ReleaseManifest:
        return ReleaseManifest(
            channel="dev",
            helper_version="1.2.3",
            release_label="1.2.3-dev",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        )

    def resolve_path(root: Path, value: str | Path) -> Path:
        path = Path(value)
        return path if path.is_absolute() else root / path

    def verify_bundle(bundle_path: Path) -> None:
        nonlocal verified_path
        verified_path = bundle_path

    monkeypatch.setattr(macos_update_bundle_usecases, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_macos_release_settings",
        lambda config, root: SimpleNamespace(dist_dir=root / "dist"),
    )
    monkeypatch.setattr(macos_update_bundle_usecases, "resolve_path", resolve_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_release_manifest",
        load_release_manifest,
    )
    monkeypatch.setattr(macos_update_bundle_usecases, "verify_bundle", verify_bundle)

    macos_update_bundle_usecases.verify_update_bundle(
        VerifyReleaseUpdateBundleInput(
            config=Path("config/vm-build.toml"),
            release_file=Path("release.json"),
            bundle_name=None,
            bundle_kind="product-update",
            output_dir=Path("custom-bundles"),
        )
    )

    assert verified_path == (
        tmp_path
        / "custom-bundles"
        / "update-bundle-dev-product-update-1.2.3-dev.tar.gz"
    )


def test_apply_smoke_release_update_bundle_uses_installed_cli(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    bundle_dir = tmp_path / "custom-bundles"
    bundle_dir.mkdir()
    bundle_path = bundle_dir / "update-bundle-dev-product-update-1.2.3-dev.tar.gz"
    bundle_path.write_text("bundle", encoding="utf-8")
    vm_cli = tmp_path / "bin/vitalserver-vm"
    vm_cli.parent.mkdir()
    vm_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    vm_cli.chmod(0o755)
    commands: list[list[str]] = []

    def load_release_manifest(path: Path) -> ReleaseManifest:
        return ReleaseManifest(
            channel="dev",
            helper_version="1.2.3",
            release_label="1.2.3-dev",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        )

    def resolve_path(root: Path, value: str | Path) -> Path:
        path = Path(value)
        return path if path.is_absolute() else root / path

    monkeypatch.setattr(macos_update_bundle_usecases, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_macos_release_settings",
        lambda config, root: SimpleNamespace(
            dist_dir=root / "dist",
            install=SimpleNamespace(vm_cli=str(vm_cli)),
        ),
    )
    monkeypatch.setattr(macos_update_bundle_usecases, "resolve_path", resolve_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_release_manifest",
        load_release_manifest,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases.subprocess,
        "run",
        lambda command, check, text, capture_output: SimpleNamespace(
            returncode=0,
            stdout="",
            stderr="",
            _recorded=commands.append(command),
        ),
    )

    macos_update_bundle_usecases.apply_smoke_update_bundle(
        ApplySmokeReleaseUpdateBundleInput(
            config=Path("config/vm-build.toml"),
            release_file=Path("release-dev.json"),
            bundle_name=None,
            bundle_kind="product-update",
            output_dir=Path("custom-bundles"),
        )
    )

    assert commands == [
        [
            "sudo",
            str(vm_cli),
            "runtime",
            "apply-bundle",
            str(bundle_path),
            "--allow-unsigned-dev-bundle",
        ]
    ]


def test_apply_smoke_release_update_bundle_rejects_stable_channel_before_sudo(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    bundle_dir = tmp_path / "custom-bundles"
    bundle_dir.mkdir()
    bundle_path = bundle_dir / "update-bundle-stable-product-update-1.2.3.tar.gz"
    bundle_path.write_text("bundle", encoding="utf-8")
    vm_cli = tmp_path / "bin/vitalserver-vm"
    vm_cli.parent.mkdir()
    vm_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    vm_cli.chmod(0o755)
    commands: list[list[str]] = []

    monkeypatch.setattr(macos_update_bundle_usecases, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_macos_release_settings",
        lambda config, root: SimpleNamespace(
            dist_dir=root / "dist",
            install=SimpleNamespace(vm_cli=str(vm_cli)),
        ),
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "resolve_path",
        lambda root, value: Path(value) if Path(value).is_absolute() else root / value,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_release_manifest",
        lambda path: ReleaseManifest(
            channel="stable",
            helper_version="1.2.3",
            release_label="1.2.3",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        ),
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases.subprocess,
        "run",
        lambda *args, **kwargs: commands.append(list(args[0])),
    )

    with pytest.raises(
        SystemExit,
        match=(
            "legacy stable update apply smoke is unavailable because "
            "trusted publisher verification is not implemented"
        ),
    ):
        macos_update_bundle_usecases.apply_smoke_update_bundle(
            ApplySmokeReleaseUpdateBundleInput(
                config=Path("config/vm-build.toml"),
                release_file=Path("release.json"),
                bundle_name=None,
                bundle_kind="product-update",
                output_dir=Path("custom-bundles"),
            )
        )

    assert commands == []


def test_apply_smoke_release_update_bundle_reports_sudo_failure(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    bundle_dir = tmp_path / "custom-bundles"
    bundle_dir.mkdir()
    bundle_path = bundle_dir / "update-bundle-dev-product-update-1.2.3-dev.tar.gz"
    bundle_path.write_text("bundle", encoding="utf-8")
    vm_cli = tmp_path / "bin/vitalserver-vm"
    vm_cli.parent.mkdir()
    vm_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    vm_cli.chmod(0o755)

    def load_release_manifest(path: Path) -> ReleaseManifest:
        return ReleaseManifest(
            channel="dev",
            helper_version="1.2.3",
            release_label="1.2.3-dev",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        )

    def resolve_path(root: Path, value: str | Path) -> Path:
        path = Path(value)
        return path if path.is_absolute() else root / path

    monkeypatch.setattr(macos_update_bundle_usecases, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_macos_release_settings",
        lambda config, root: SimpleNamespace(
            dist_dir=root / "dist",
            install=SimpleNamespace(vm_cli=str(vm_cli)),
        ),
    )
    monkeypatch.setattr(macos_update_bundle_usecases, "resolve_path", resolve_path)
    monkeypatch.setattr(
        macos_update_bundle_usecases,
        "load_release_manifest",
        load_release_manifest,
    )
    monkeypatch.setattr(
        macos_update_bundle_usecases.subprocess,
        "run",
        lambda command, check, text, capture_output: subprocess.CompletedProcess(
            command,
            1,
            stdout="",
            stderr="sudo: a password is required\n",
        ),
    )

    with pytest.raises(SystemExit) as error:
        macos_update_bundle_usecases.apply_smoke_update_bundle(
            ApplySmokeReleaseUpdateBundleInput(
                config=Path("config/vm-build.toml"),
                release_file=Path("release-dev.json"),
                bundle_name=None,
                bundle_kind="product-update",
                output_dir=Path("custom-bundles"),
            )
        )

    assert "update apply smoke failed exitCode=1" in str(error.value)
    assert "interactive administrator shell" in str(error.value)
