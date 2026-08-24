from __future__ import annotations

import base64
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
    specification, payload_root = write_specification(
        tmp_path,
        update_id="helper-update-0.2.2",
        layer_order=["container", "guest-runtime", "host-platform"],
    )
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
            payload_root=payload_root,
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
        names = set(archive.getnames())
        envelope_file = archive.extractfile(f"{root}/bootstrap-envelope.json")
        assert envelope_file is not None
        envelope = json.loads(envelope_file.read())
    assert f"{root}/payload/layers/host-platform/executor" in names
    assert f"{root}/payload/layers/guest-runtime/configuration.json" in names
    assert f"{root}/payload/layers/container/rollback.bin" in names
    unsigned = dict(envelope)
    unsigned.pop("signature")
    assert (
        canonical_payload(unsigned)
        .decode("utf-8")
        .startswith(
            '{"schemaVersion":"v2","id":"helper-update-0.2.2",'
            '"productId":"ai.tirosh.vitalserver.helper",'
            '"target":{"platform":"macos","architecture":"arm64"},'
        )
    )
    assert "minUpdaterVersion" not in envelope
    assert "requiresTwoPhaseUpdate" not in envelope
    payload_paths = {entry["relativePath"] for entry in envelope["payloadArtifacts"]}
    assert payload_paths == {
        "payload/layers/host-platform/apply.bin",
        "payload/layers/host-platform/executor",
        "payload/layers/host-platform/configuration.json",
        "payload/layers/host-platform/rollback.bin",
        "payload/layers/guest-runtime/apply.bin",
        "payload/layers/guest-runtime/executor",
        "payload/layers/guest-runtime/configuration.json",
        "payload/layers/guest-runtime/rollback.bin",
        "payload/layers/container/apply.bin",
        "payload/layers/container/executor",
        "payload/layers/container/configuration.json",
        "payload/layers/container/rollback.bin",
    }


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
    specification, payload_root = write_specification(
        tmp_path,
        update_id="update-42",
        layer_order=["host-platform"],
    )
    updater.write_bytes(b"updater")
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
                payload_root=payload_root,
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
    specification, payload_root = write_specification(
        tmp_path,
        update_id="update-42",
        layer_order=["host-platform"],
    )

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
                payload_root=payload_root,
                publisher_key_id="release-key",
                publisher_private_key=private_key,
                issued_at="2026-07-27T00:00:00Z",
                output=tmp_path / "bundle.tar.gz",
            )
        )


def test_builder_rejects_payload_that_does_not_match_specification(
    tmp_path: Path,
) -> None:
    private_key, _ = signing_keys(tmp_path)
    updater = tmp_path / "updater"
    updater.write_bytes(b"updater")
    specification, payload_root = write_specification(
        tmp_path,
        update_id="update-42",
        layer_order=["host-platform"],
    )
    (payload_root / "payload/layers/host-platform/apply.bin").write_bytes(
        b"modified after specification"
    )

    with pytest.raises(DomainError, match="artifact digest mismatch"):
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
                payload_root=payload_root,
                publisher_key_id="release-key",
                publisher_private_key=private_key,
                issued_at="2026-07-27T00:00:00Z",
                output=tmp_path / "bundle.tar.gz",
            )
        )


def test_verifier_rejects_missing_specification_artifact(tmp_path: Path) -> None:
    private_key, public_key = signing_keys(tmp_path)
    root = build_and_extract(tmp_path, private_key)
    (root / "payload/layers/host-platform/rollback.bin").unlink()

    with pytest.raises(DomainError, match="file closure differs"):
        bootstrap_bundle_service.verify_bootstrap_bundle_directory(root, public_key)


def test_verifier_rejects_extra_regular_file_outside_signed_closure(
    tmp_path: Path,
) -> None:
    private_key, public_key = signing_keys(tmp_path)
    root = build_and_extract(tmp_path, private_key)
    (root / "payload/layers/host-platform/extra.bin").write_bytes(b"extra")

    with pytest.raises(DomainError, match="file closure differs"):
        bootstrap_bundle_service.verify_bootstrap_bundle_directory(root, public_key)


def test_envelope_rejects_duplicate_payload_artifact(tmp_path: Path) -> None:
    with pytest.raises(DomainError, match="duplicate path"):
        unsigned_envelope(
            update_id="update-42",
            product_version="0.2.2",
            runtime_version="0.2.2",
            target_platform="macos",
            target_architecture="arm64",
            layer_order=["host-platform"],
            next_updater_artifact={
                "id": "next-updater",
                "relativePath": "payload/bin/vitalserver-update",
                "sha256": "a" * 64,
                "sizeBytes": 7,
                "mediaType": "application/octet-stream",
            },
            specification_artifact={
                "id": "specification",
                "relativePath": "payload/update-specification.json",
                "sha256": "b" * 64,
                "sizeBytes": 8,
                "mediaType": "application/json",
            },
            payload_artifacts=[
                {
                    "id": "host-apply",
                    "relativePath": "payload/layers/host-platform/apply.bin",
                    "sha256": "c" * 64,
                    "sizeBytes": 9,
                    "mediaType": "application/octet-stream",
                },
                {
                    "id": "host-apply-2",
                    "relativePath": "payload/layers/host-platform/apply.bin",
                    "sha256": "d" * 64,
                    "sizeBytes": 10,
                    "mediaType": "application/octet-stream",
                },
            ],
            issued_at="2026-07-27T00:00:00Z",
        )


def test_envelope_accepts_real_utc_leap_day_instant() -> None:
    envelope = _minimal_unsigned_envelope(issued_at="2024-02-29T23:59:59Z")
    assert envelope["issuedAt"] == "2024-02-29T23:59:59Z"


@pytest.mark.parametrize(
    "issued_at",
    [
        "2026-02-30T00:00:00Z",
        "2026-13-01T00:00:00Z",
        "2026-00-01T00:00:00Z",
        "2026-01-00T00:00:00Z",
        "2026-01-32T00:00:00Z",
        "2026-01-01T24:00:00Z",
        "2026-01-01T23:60:00Z",
        "2026-01-01T23:59:60Z",
        "2025-02-29T00:00:00Z",
        "2026-04-31T00:00:00Z",
    ],
)
def test_envelope_rejects_issued_at_that_is_not_a_real_utc_instant(
    issued_at: str,
) -> None:
    with pytest.raises(DomainError, match="issuedAt"):
        _minimal_unsigned_envelope(issued_at=issued_at)


def _minimal_unsigned_envelope(issued_at: str) -> dict[str, object]:
    return unsigned_envelope(
        update_id="update-42",
        product_version="0.2.2",
        runtime_version="0.2.2",
        target_platform="macos",
        target_architecture="arm64",
        layer_order=["host-platform"],
        next_updater_artifact={
            "id": "next-updater",
            "relativePath": "payload/bin/vitalserver-update",
            "sha256": "a" * 64,
            "sizeBytes": 7,
            "mediaType": "application/octet-stream",
        },
        specification_artifact={
            "id": "specification",
            "relativePath": "payload/update-specification.json",
            "sha256": "b" * 64,
            "sizeBytes": 8,
            "mediaType": "application/json",
        },
        payload_artifacts=[
            {
                "id": "host-apply",
                "relativePath": "payload/layers/host-platform/apply.bin",
                "sha256": "c" * 64,
                "sizeBytes": 9,
                "mediaType": "application/octet-stream",
            },
        ],
        issued_at=issued_at,
    )


def test_verifier_reports_invalid_archive_as_domain_failure(tmp_path: Path) -> None:
    _, public_key = signing_keys(tmp_path)
    bundle = tmp_path / "invalid.tar.gz"
    bundle.write_bytes(b"not an archive")

    with pytest.raises(DomainError, match="materialization failed"):
        bootstrap_bundle_service.verify_bootstrap_bundle(bundle, public_key)


def test_trust_store_verifier_uses_envelope_key_id(tmp_path: Path) -> None:
    private_key, public_key = signing_keys(tmp_path)
    build_and_extract(tmp_path, private_key)
    trust_store = write_trust_store(
        tmp_path,
        public_key,
        key_id="release-key",
        state="active",
    )

    bootstrap_bundle_service.verify_bootstrap_bundle_with_trust_store(
        tmp_path / "bundle.tar.gz",
        trust_store,
    )


@pytest.mark.parametrize(
    ("key_id", "state", "message"),
    [
        ("different-key", "active", "publisher key is unknown"),
        ("release-key", "revoked", "publisher key is revoked"),
    ],
)
def test_trust_store_verifier_rejects_untrusted_publisher_state(
    tmp_path: Path,
    key_id: str,
    state: str,
    message: str,
) -> None:
    private_key, public_key = signing_keys(tmp_path)
    build_and_extract(tmp_path, private_key)
    trust_store = write_trust_store(
        tmp_path,
        public_key,
        key_id=key_id,
        state=state,
    )

    with pytest.raises(DomainError, match=message):
        bootstrap_bundle_service.verify_bootstrap_bundle_with_trust_store(
            tmp_path / "bundle.tar.gz",
            trust_store,
        )


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
        payload_artifacts=[
            {
                "id": "host-platform-apply",
                "relativePath": "payload/layers/host-platform/apply.bin",
                "sha256": "c" * 64,
                "sizeBytes": 9,
                "mediaType": "application/octet-stream",
            },
        ],
        issued_at="2026-07-27T00:00:00Z",
    )

    assert canonical_payload(unsigned).decode("utf-8") == (
        '{"schemaVersion":"v2","id":"helper-update-0.2.2",'
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
        '"payloadArtifacts":[{"id":"host-platform-apply",'
        '"relativePath":"payload/layers/host-platform/apply.bin",'
        f'"sha256":"{"c" * 64}","sizeBytes":9,'
        '"mediaType":"application/octet-stream"}],'
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


def write_trust_store(
    root: Path,
    public_key: Path,
    *,
    key_id: str,
    state: str,
) -> Path:
    decoded = serialization.load_pem_public_key(public_key.read_bytes())
    trust_store = root / "publisher-trust-store.json"
    trust_store.write_text(
        json.dumps(
            {
                "schemaVersion": "v2",
                "keys": [
                    {
                        "id": key_id,
                        "algorithm": "ed25519",
                        "publicKey": base64.b64encode(
                            decoded.public_bytes(
                                encoding=serialization.Encoding.Raw,
                                format=serialization.PublicFormat.Raw,
                            )
                        ).decode("ascii"),
                        "state": state,
                    }
                ],
            }
        )
        + "\n",
        encoding="utf-8",
    )
    return trust_store


def build_and_extract(root: Path, private_key: Path) -> Path:
    updater = root / "updater"
    updater.write_bytes(b"updater")
    specification, payload_root = write_specification(
        root,
        update_id="update-42",
        layer_order=["host-platform"],
    )
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
            payload_root=payload_root,
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


def write_specification(
    root: Path,
    *,
    update_id: str,
    layer_order: list[str],
) -> tuple[Path, Path]:
    payload_root = root / "prepared-payload"
    layer_plan: list[dict[str, object]] = []
    prior_layers: list[str] = []
    for layer in layer_order:
        payload = write_artifact(
            payload_root,
            artifact_id=f"{layer}-payload",
            relative_path=f"payload/layers/{layer}/apply.bin",
            contents=f"{layer} apply".encode(),
        )
        executor = write_artifact(
            payload_root,
            artifact_id=f"{layer}-executor",
            relative_path=f"payload/layers/{layer}/executor",
            contents=f"{layer} executor".encode(),
        )
        (payload_root / executor["relativePath"]).chmod(0o755)
        configuration = write_artifact(
            payload_root,
            artifact_id=f"{layer}-configuration",
            relative_path=f"payload/layers/{layer}/configuration.json",
            contents=b"{}\n",
            media_type="application/json",
        )
        rollback = write_artifact(
            payload_root,
            artifact_id=f"{layer}-rollback",
            relative_path=f"payload/layers/{layer}/rollback.bin",
            contents=f"{layer} rollback".encode(),
        )
        layer_plan.append(
            {
                "layer": layer,
                "dependsOn": list(prior_layers),
                "artifact": payload,
                "effectExecutor": {
                    **executor,
                    "configurationArtifact": configuration,
                },
                "rollback": {
                    "state": "available",
                    "artifact": rollback,
                    "reason": None,
                },
            }
        )
        prior_layers.append(layer)
    specification = root / "update-specification.json"
    specification.write_text(
        json.dumps(
            {
                "schemaVersion": (
                    "vitalserver.product-update-specification/v1"
                ),
                "id": f"{update_id}-specification",
                "bootstrapEnvelopeId": update_id,
                "layerPlan": layer_plan,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return specification, payload_root


def write_artifact(
    root: Path,
    *,
    artifact_id: str,
    relative_path: str,
    contents: bytes,
    media_type: str = "application/octet-stream",
) -> dict[str, object]:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(contents)
    return {
        "id": artifact_id,
        "relativePath": relative_path,
        "sha256": bootstrap_bundle_service.sha256_file(path),
        "sizeBytes": len(contents),
        "mediaType": media_type,
    }
