from __future__ import annotations

import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest
from pytest import MonkeyPatch

from tirosh_vitalserver.devtools.application.inputs import (
    ApplySmokeReleaseUpdateBundleInput,
    VerifyReleaseUpdateBundleInput,
)
from tirosh_vitalserver.devtools.application.usecases import (
    macos_update_bundle as macos_update_bundle_usecases,
)
from tirosh_vitalserver.devtools.core.release_manifest import ReleaseManifest


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
            minimum_updater_version="1.0.0",
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
            minimum_updater_version="1.0.0",
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
            release_file=Path("release.json"),
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
        ]
    ]


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
            minimum_updater_version="1.0.0",
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
                release_file=Path("release.json"),
                bundle_name=None,
                bundle_kind="product-update",
                output_dir=Path("custom-bundles"),
            )
        )

    assert "update apply smoke failed exitCode=1" in str(error.value)
    assert "interactive administrator shell" in str(error.value)
