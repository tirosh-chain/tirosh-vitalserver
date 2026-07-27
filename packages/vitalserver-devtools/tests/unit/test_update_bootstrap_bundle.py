from __future__ import annotations

import json
import tarfile
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from tirosh_vitalserver.devtools.adapters.update_bundle import (
    bootstrap_bundle_service,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle import (
    canonical_payload,
    unsigned_envelope,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle_models import (
    BuildUpdateBootstrapBundleInput,
)


def test_builds_signed_closure_matching_swift_canonical_contract(
    tmp_path: Path,
) -> None:
    private_key, public_key = signing_keys(tmp_path)
    updater = tmp_path / "vitalserver-update"
    updater.write_bytes(b"next updater")
    updater.chmod(0o755)
    specification = tmp_path / "update-specification.json"
    specification.write_text('{"schemaVersion":"v1"}\n', encoding="utf-8")
    output = tmp_path / "helper-update-0.2.2.tar.gz"

    result = bootstrap_bundle_service.build_bootstrap_bundle(
        BuildUpdateBootstrapBundleInput(
            update_id="helper-update-0.2.2",
            product_version="0.2.2",
            runtime_version="0.2.2",
            target_platform="macos",
            target_architecture="arm64",
            layer_order=["container", "guest-runtime", "host-platform"],
            next_updater=updater,
            specification=specification,
            publisher_key_id="helper-release-key-2026",
            publisher_private_key=private_key,
            issued_at="2026-07-27T00:00:00Z",
            output=output,
        )
    )

    assert result.archive == output
    assert len(result.envelope_sha256) == 64
    bootstrap_bundle_service.verify_bootstrap_bundle(output, public_key)
    with tarfile.open(output, "r:gz") as archive:
        root = "update-bootstrap-helper-update-0.2.2"
        envelope_file = archive.extractfile(f"{root}/bootstrap-envelope.json")
        assert envelope_file is not None
        envelope = json.loads(envelope_file.read())
    unsigned = dict(envelope)
    unsigned.pop("signature")
    assert (
        canonical_payload(unsigned)
        .decode("utf-8")
        .startswith(
            '{"schemaVersion":"v1","id":"helper-update-0.2.2",'
            '"productId":"ai.tirosh.vitalserver.helper",'
            '"target":{"platform":"macos","architecture":"arm64"},'
        )
    )
    assert "minUpdaterVersion" not in envelope
    assert "requiresTwoPhaseUpdate" not in envelope


def test_verifier_rejects_artifact_modified_after_signing(tmp_path: Path) -> None:
    private_key, public_key = signing_keys(tmp_path)
    root = build_and_extract(tmp_path, private_key)
    (root / "payload/update-specification.json").write_text(
        '{"modified":true}\n',
        encoding="utf-8",
    )

    with pytest.raises(DomainError, match="artifact digest mismatch"):
        bootstrap_bundle_service.verify_bootstrap_bundle_directory(root, public_key)


def test_builder_does_not_replace_existing_release_artifact(tmp_path: Path) -> None:
    private_key, _ = signing_keys(tmp_path)
    updater = tmp_path / "updater"
    specification = tmp_path / "specification.json"
    updater.write_bytes(b"updater")
    specification.write_bytes(b"specification")
    output = tmp_path / "existing.tar.gz"
    output.write_bytes(b"operator-owned")

    with pytest.raises(DomainError, match="output already exists"):
        bootstrap_bundle_service.build_bootstrap_bundle(
            BuildUpdateBootstrapBundleInput(
                update_id="update-42",
                product_version="0.2.2",
                runtime_version="0.2.2",
                target_platform="macos",
                target_architecture="arm64",
                layer_order=["host-platform"],
                next_updater=updater,
                specification=specification,
                publisher_key_id="release-key",
                publisher_private_key=private_key,
                issued_at="2026-07-27T00:00:00Z",
                output=output,
            )
        )
    assert output.read_bytes() == b"operator-owned"


def test_builder_rejects_symlinked_updater(tmp_path: Path) -> None:
    private_key, _ = signing_keys(tmp_path)
    real = tmp_path / "real-updater"
    real.write_bytes(b"updater")
    updater = tmp_path / "updater"
    updater.symlink_to(real)
    specification = tmp_path / "specification.json"
    specification.write_bytes(b"specification")

    with pytest.raises(DomainError, match="must be a regular file"):
        bootstrap_bundle_service.build_bootstrap_bundle(
            BuildUpdateBootstrapBundleInput(
                update_id="update-42",
                product_version="0.2.2",
                runtime_version="0.2.2",
                target_platform="macos",
                target_architecture="arm64",
                layer_order=["host-platform"],
                next_updater=updater,
                specification=specification,
                publisher_key_id="release-key",
                publisher_private_key=private_key,
                issued_at="2026-07-27T00:00:00Z",
                output=tmp_path / "bundle.tar.gz",
            )
        )


def test_verifier_reports_invalid_archive_as_domain_failure(tmp_path: Path) -> None:
    _, public_key = signing_keys(tmp_path)
    bundle = tmp_path / "invalid.tar.gz"
    bundle.write_bytes(b"not an archive")

    with pytest.raises(DomainError, match="materialization failed"):
        bootstrap_bundle_service.verify_bootstrap_bundle(bundle, public_key)


def test_verifier_rejects_unknown_symlink_in_bundle(tmp_path: Path) -> None:
    private_key, public_key = signing_keys(tmp_path)
    root = build_and_extract(tmp_path, private_key)
    (root / "unknown-link").symlink_to(root / "bootstrap-envelope.json")

    with pytest.raises(
        DomainError,
        match="bootstrap bundle entry must be a regular file",
    ):
        bootstrap_bundle_service.verify_bootstrap_bundle_directory(root, public_key)


def test_canonical_payload_matches_swift_consumer_contract() -> None:
    unsigned = unsigned_envelope(
        update_id="helper-update-0.2.2",
        product_version="0.2.2",
        runtime_version="0.2.2",
        target_platform="macos",
        target_architecture="arm64",
        layer_order=["container", "guest-runtime", "host-platform"],
        next_updater_artifact={
            "id": "helper-next-updater",
            "relativePath": "payload/bin/vitalserver-update",
            "sha256": "a" * 64,
            "sizeBytes": 7,
            "mediaType": "application/octet-stream",
        },
        specification_artifact={
            "id": "helper-update-specification",
            "relativePath": "payload/update-specification.json",
            "sha256": "b" * 64,
            "sizeBytes": 8,
            "mediaType": "application/json",
        },
        issued_at="2026-07-27T00:00:00Z",
    )

    assert canonical_payload(unsigned).decode("utf-8") == (
        '{"schemaVersion":"v1","id":"helper-update-0.2.2",'
        '"productId":"ai.tirosh.vitalserver.helper",'
        '"target":{"platform":"macos","architecture":"arm64"},'
        '"targetRelease":{"productVersion":"0.2.2","runtimeVersion":"0.2.2"},'
        '"layerOrder":["container","guest-runtime","host-platform"],'
        '"nextUpdaterArtifact":{"id":"helper-next-updater",'
        '"relativePath":"payload/bin/vitalserver-update",'
        f'"sha256":"{"a" * 64}","sizeBytes":7,'
        '"mediaType":"application/octet-stream"},'
        '"specification":{"id":"helper-update-specification",'
        '"relativePath":"payload/update-specification.json",'
        f'"sha256":"{"b" * 64}","sizeBytes":8,'
        '"mediaType":"application/json"},'
        '"issuedAt":"2026-07-27T00:00:00Z"}'
    )


def signing_keys(root: Path) -> tuple[Path, Path]:
    private_key = root / "publisher-private.pem"
    public_key = root / "publisher-public.pem"
    key = Ed25519PrivateKey.generate()
    private_key.write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    public_key.write_bytes(
        key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    )
    return private_key, public_key


def build_and_extract(root: Path, private_key: Path) -> Path:
    updater = root / "updater"
    specification = root / "specification.json"
    updater.write_bytes(b"updater")
    specification.write_bytes(b"specification")
    output = root / "bundle.tar.gz"
    bootstrap_bundle_service.build_bootstrap_bundle(
        BuildUpdateBootstrapBundleInput(
            update_id="update-42",
            product_version="0.2.2",
            runtime_version="0.2.2",
            target_platform="macos",
            target_architecture="arm64",
            layer_order=["host-platform"],
            next_updater=updater,
            specification=specification,
            publisher_key_id="release-key",
            publisher_private_key=private_key,
            issued_at="2026-07-27T00:00:00Z",
            output=output,
        )
    )
    extracted = root / "extracted"
    with tarfile.open(output, "r:gz") as archive:
        archive.extractall(extracted, filter="data")
    return extracted / "update-bootstrap-update-42"
