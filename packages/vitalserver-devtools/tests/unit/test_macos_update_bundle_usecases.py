from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from pytest import MonkeyPatch

from tirosh_vitalserver.devtools.application.inputs import (
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
