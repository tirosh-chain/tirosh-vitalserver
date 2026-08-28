from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from tirosh_vitalserver.devtools import cli
from tirosh_vitalserver.devtools.adapters.update_bundle import trust_store_service
from tirosh_vitalserver.devtools.application.usecases import (
    update_bootstrap_trust_store,
)
from tirosh_vitalserver.devtools.core.errors import DomainError


def test_create_rotate_and_revoke_preserve_explicit_key_lifecycle(
    tmp_path: Path,
) -> None:
    first_public, first_private = write_public_key(tmp_path, "first")
    second_public, _ = write_public_key(tmp_path, "second")
    initial = tmp_path / "trust-v1.json"
    rotated = tmp_path / "trust-v2.json"
    revoked = tmp_path / "trust-v3.json"
    operations = real_operations()

    assert update_bootstrap_trust_store.create(
        publisher_key_id="release-2026-a",
        publisher_public_key=first_public,
        output=initial,
        operations=operations,
    ) == 0
    assert update_bootstrap_trust_store.rotate(
        trust_store=initial,
        publisher_key_id="release-2026-b",
        publisher_public_key=second_public,
        output=rotated,
        operations=operations,
    ) == 0
    assert update_bootstrap_trust_store.revoke(
        trust_store=rotated,
        publisher_key_id="release-2026-a",
        output=revoked,
        operations=operations,
    ) == 0

    initial_document = json.loads(initial.read_text())
    rotated_document = json.loads(rotated.read_text())
    revoked_document = json.loads(revoked.read_text())
    assert initial_document["schemaVersion"] == "v2"
    assert [(key["id"], key["state"]) for key in rotated_document["keys"]] == [
        ("release-2026-a", "active"),
        ("release-2026-b", "active"),
    ]
    assert [(key["id"], key["state"]) for key in revoked_document["keys"]] == [
        ("release-2026-a", "revoked"),
        ("release-2026-b", "active"),
    ]
    assert first_private.read_text() not in revoked.read_text()
    assert revoked.read_bytes().endswith(b"\n")


def test_rotation_rejects_duplicate_key_id(tmp_path: Path) -> None:
    public_key, _ = write_public_key(tmp_path, "publisher")
    initial = tmp_path / "initial.json"
    operations = real_operations()
    update_bootstrap_trust_store.create(
        publisher_key_id="release-key",
        publisher_public_key=public_key,
        output=initial,
        operations=operations,
    )

    with pytest.raises(DomainError, match="duplicated"):
        update_bootstrap_trust_store.rotate(
            trust_store=initial,
            publisher_key_id="release-key",
            publisher_public_key=public_key,
            output=tmp_path / "duplicate.json",
            operations=operations,
        )


@pytest.mark.parametrize("key_id", ["unknown-key", "release-key"])
def test_revoke_rejects_unknown_or_already_revoked_key(
    tmp_path: Path,
    key_id: str,
) -> None:
    public_key, _ = write_public_key(tmp_path, "publisher")
    initial = tmp_path / "initial.json"
    revoked = tmp_path / "revoked.json"
    operations = real_operations()
    update_bootstrap_trust_store.create(
        publisher_key_id="release-key",
        publisher_public_key=public_key,
        output=initial,
        operations=operations,
    )
    input_store = initial
    if key_id == "release-key":
        update_bootstrap_trust_store.revoke(
            trust_store=initial,
            publisher_key_id=key_id,
            output=revoked,
            operations=operations,
        )
        input_store = revoked

    with pytest.raises(DomainError, match=r"unknown|already revoked"):
        update_bootstrap_trust_store.revoke(
            trust_store=input_store,
            publisher_key_id=key_id,
            output=tmp_path / "rejected.json",
            operations=operations,
        )


def test_public_key_and_store_inputs_fail_closed(tmp_path: Path) -> None:
    missing = tmp_path / "missing.pem"
    with pytest.raises(DomainError, match="unavailable"):
        trust_store_service.read_ed25519_public_key(missing)

    invalid = tmp_path / "invalid.pem"
    invalid.write_text("not a public key")
    with pytest.raises(DomainError, match="decode failed"):
        trust_store_service.read_ed25519_public_key(invalid)

    invalid_store = tmp_path / "invalid.json"
    invalid_store.write_text('{"schemaVersion":"v2","keys":[]}')
    with pytest.raises(DomainError, match="is invalid"):
        trust_store_service.read_trust_store(invalid_store)


def test_release_cli_materializes_public_only_trust_store(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    public_key, private_key = write_public_key(tmp_path, "publisher")
    output = tmp_path / "release-trust-store.json"
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "vitalserver-devtools",
            "update-bootstrap-trust-store-create",
            "--publisher-key-id",
            "release-key",
            "--publisher-public-key",
            str(public_key),
            "--output",
            str(output),
        ],
    )

    assert cli.main() == 0
    assert json.loads(output.read_text())["keys"][0]["state"] == "active"
    assert private_key.read_text() not in output.read_text()


@pytest.mark.parametrize(
    "missing_option",
    ["--publisher-key-id", "--publisher-private-key"],
)
def test_release_signing_cli_requires_explicit_key_identity_and_private_key(
    monkeypatch: pytest.MonkeyPatch,
    missing_option: str,
) -> None:
    arguments = [
        "vitalserver-devtools",
        "update-bootstrap-bundle",
        "--update-id",
        "update-1",
        "--product-version",
        "0.2.2",
        "--runtime-version",
        "0.2.2",
        "--target-platform",
        "macos",
        "--target-architecture",
        "arm64",
        "--layer",
        "host-platform",
        "--next-updater",
        "/tmp/updater",
        "--specification",
        "/tmp/specification.json",
        "--payload-root",
        "/tmp/payload",
        "--publisher-key-id",
        "release-key",
        "--publisher-private-key",
        "/secure/release/private.pem",
        "--issued-at",
        "2026-07-29T00:00:00Z",
        "--output",
        "/tmp/update.tar.gz",
    ]
    option_index = arguments.index(missing_option)
    del arguments[option_index: option_index + 2]
    monkeypatch.setattr(sys, "argv", arguments)

    with pytest.raises(SystemExit) as raised:
        cli.main()

    assert raised.value.code == 2


def real_operations(
) -> update_bootstrap_trust_store.UpdateBootstrapTrustStoreOperations:
    return update_bootstrap_trust_store.UpdateBootstrapTrustStoreOperations(
        read_store=trust_store_service.read_trust_store,
        read_ed25519_public_key=trust_store_service.read_ed25519_public_key,
        write_new_store=trust_store_service.write_new_store,
    )


def write_public_key(tmp_path: Path, name: str) -> tuple[Path, Path]:
    private_key = Ed25519PrivateKey.generate()
    private_path = tmp_path / f"{name}-private.pem"
    public_path = tmp_path / f"{name}-public.pem"
    private_path.write_bytes(
        private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    public_path.write_bytes(
        private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    )
    return public_path, private_path
