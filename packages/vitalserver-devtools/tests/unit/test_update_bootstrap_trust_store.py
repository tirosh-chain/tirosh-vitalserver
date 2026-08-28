import base64
import json
from collections.abc import Callable
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.config.update_bootstrap_trust_store import (
    UpdateBootstrapTrustStoreDecodeError,
    UpdateBootstrapTrustStoreInvalidError,
    UpdateBootstrapTrustStoreReadError,
    UpdateBootstrapTrustStoreUnavailableError,
    load_update_bootstrap_trust_store,
)
from tirosh_vitalserver.devtools.core.update_bootstrap_trust_store import (
    require_active_publisher_key,
    validate_update_bootstrap_trust_store,
)

PUBLIC_KEY = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="


def valid_document() -> dict[str, object]:
    return {
        "schemaVersion": "v2",
        "keys": [
            {
                "id": "helper-release-key-2026",
                "algorithm": "ed25519",
                "publicKey": PUBLIC_KEY,
                "state": "active",
            }
        ],
    }


def test_validates_explicit_ed25519_public_key_contract() -> None:
    validate_update_bootstrap_trust_store(valid_document())


def test_resolves_only_active_key_by_explicit_publisher_id() -> None:
    assert require_active_publisher_key(
        valid_document(),
        key_id="helper-release-key-2026",
    ) == base64.b64decode(PUBLIC_KEY)


@pytest.mark.parametrize(
    ("key_id", "state", "message"),
    [
        ("unknown-key", "active", "publisher key is unknown"),
        ("helper-release-key-2026", "revoked", "publisher key is revoked"),
    ],
)
def test_active_key_resolution_preserves_unknown_and_revoked(
    key_id: str,
    state: str,
    message: str,
) -> None:
    document = valid_document()
    document["keys"][0]["state"] = state

    with pytest.raises(ValueError, match=message):
        require_active_publisher_key(document, key_id=key_id)


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        (
            lambda document: document.update({"unknown": True}),
            "contains unknown fields",
        ),
        (
            lambda document: document.update({"keys": []}),
            "non-empty array",
        ),
        (
            lambda document: document["keys"].append(document["keys"][0].copy()),
            "key id is duplicated",
        ),
        (
            lambda document: document["keys"][0].update({"algorithm": "rsa"}),
            "algorithm must be ed25519",
        ),
        (
            lambda document: document["keys"][0].update({"publicKey": "%%%"}),
            "not valid base64",
        ),
        (
            lambda document: document["keys"][0].update({"publicKey": "YQ=="}),
            "decode to 32 bytes",
        ),
    ],
)
def test_rejects_invalid_or_ambiguous_contract(
    mutate: Callable[[dict[str, object]], object],
    message: str,
) -> None:
    document = valid_document()
    mutate(document)

    with pytest.raises(ValueError, match=message):
        validate_update_bootstrap_trust_store(document)


def test_loader_rejects_missing_file(tmp_path: Path) -> None:
    path = tmp_path / "missing.json"

    with pytest.raises(
        UpdateBootstrapTrustStoreUnavailableError,
        match="is unavailable",
    ):
        load_update_bootstrap_trust_store(path)


def test_loader_rejects_symlink(tmp_path: Path) -> None:
    target = write_document(tmp_path / "trust-store.json")
    symlink = tmp_path / "trust-store-link.json"
    symlink.symlink_to(target)

    with pytest.raises(
        UpdateBootstrapTrustStoreInvalidError,
        match="must not be a symlink",
    ):
        load_update_bootstrap_trust_store(symlink)


def test_loader_keeps_decode_failure_distinct_from_invalid_contract(
    tmp_path: Path,
) -> None:
    path = tmp_path / "trust-store.json"
    path.write_text("{", encoding="utf-8")

    with pytest.raises(
        UpdateBootstrapTrustStoreDecodeError,
        match="decode failed",
    ):
        load_update_bootstrap_trust_store(path)


def test_loader_rejects_non_file_as_invalid(tmp_path: Path) -> None:
    path = tmp_path / "trust-store.json"
    path.mkdir()

    with pytest.raises(
        UpdateBootstrapTrustStoreInvalidError,
        match="must be a regular file",
    ):
        load_update_bootstrap_trust_store(path)


def test_loader_reports_file_read_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    path = write_document(tmp_path / "trust-store.json")

    def fail_read(_: Path) -> bytes:
        raise OSError("permission denied")

    monkeypatch.setattr(Path, "read_bytes", fail_read)

    with pytest.raises(
        UpdateBootstrapTrustStoreReadError,
        match="read failed",
    ):
        load_update_bootstrap_trust_store(path)


def test_loader_returns_only_a_validated_release_input(tmp_path: Path) -> None:
    path = write_document(tmp_path / "trust-store.json")

    assert load_update_bootstrap_trust_store(path) == path


def write_document(path: Path) -> Path:
    path.write_text(json.dumps(valid_document()) + "\n", encoding="utf-8")
    return path
