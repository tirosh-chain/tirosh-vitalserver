from __future__ import annotations

import base64
import binascii
import json
import re

IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


def validate_update_bootstrap_trust_store(
    document: object,
) -> None:
    if not isinstance(document, dict):
        raise ValueError("trust store must be a JSON object")
    require_exact_keys(document, {"schemaVersion", "keys"}, "trust store")
    if document["schemaVersion"] != "v2":
        raise ValueError("trust store schemaVersion must be v2")
    keys = document["keys"]
    if not isinstance(keys, list) or not keys:
        raise ValueError("trust store keys must be a non-empty array")
    if len(keys) > 128:
        raise ValueError("trust store must not contain more than 128 keys")

    observed: set[str] = set()
    for index, key in enumerate(keys):
        location = f"trust store keys[{index}]"
        if not isinstance(key, dict):
            raise ValueError(f"{location} must be a JSON object")
        require_exact_keys(
            key,
            {"id", "algorithm", "publicKey", "state"},
            location,
        )
        key_id = key["id"]
        if not isinstance(key_id, str) or not IDENTIFIER.fullmatch(key_id):
            raise ValueError(f"{location}.id is invalid")
        if key_id in observed:
            raise ValueError(f"trust store key id is duplicated: {key_id}")
        observed.add(key_id)
        if key["algorithm"] != "ed25519":
            raise ValueError(f"{location}.algorithm must be ed25519")
        if key["state"] not in {"active", "revoked"}:
            raise ValueError(f"{location}.state must be active or revoked")
        public_key = key["publicKey"]
        if not isinstance(public_key, str):
            raise ValueError(f"{location}.publicKey must be base64 text")
        try:
            decoded = base64.b64decode(public_key, validate=True)
        except (binascii.Error, ValueError) as error:
            raise ValueError(f"{location}.publicKey is not valid base64") from error
        if len(decoded) != 32:
            raise ValueError(f"{location}.publicKey must decode to 32 bytes")


def publisher_key_document(
    *,
    key_id: str,
    public_key: bytes,
    state: str = "active",
) -> dict[str, object]:
    document: dict[str, object] = {
        "id": key_id,
        "algorithm": "ed25519",
        "publicKey": base64.b64encode(public_key).decode("ascii"),
        "state": state,
    }
    validate_update_bootstrap_trust_store(
        {"schemaVersion": "v2", "keys": [document]}
    )
    return document


def create_update_bootstrap_trust_store(
    publisher_key: dict[str, object],
) -> dict[str, object]:
    document: dict[str, object] = {
        "schemaVersion": "v2",
        "keys": [publisher_key],
    }
    validate_update_bootstrap_trust_store(document)
    return document


def rotate_update_bootstrap_trust_store(
    document: object,
    publisher_key: dict[str, object],
) -> dict[str, object]:
    validate_update_bootstrap_trust_store(document)
    if not isinstance(document, dict) or not isinstance(document["keys"], list):
        raise ValueError("trust store contract was not preserved after validation")
    candidate: dict[str, object] = {
        "schemaVersion": "v2",
        "keys": sorted(
            [*document["keys"], publisher_key],
            key=lambda key: str(key["id"]),
        ),
    }
    validate_update_bootstrap_trust_store(candidate)
    return candidate


def revoke_update_bootstrap_publisher_key(
    document: object,
    *,
    key_id: str,
) -> dict[str, object]:
    validate_update_bootstrap_trust_store(document)
    if not IDENTIFIER.fullmatch(key_id):
        raise ValueError("publisher key id is invalid")
    if not isinstance(document, dict) or not isinstance(document["keys"], list):
        raise ValueError("trust store contract was not preserved after validation")
    keys: list[dict[str, object]] = []
    matched = False
    for key in document["keys"]:
        if key["id"] != key_id:
            keys.append(dict(key))
            continue
        matched = True
        if key["state"] == "revoked":
            raise ValueError(f"publisher key is already revoked: {key_id}")
        revoked = dict(key)
        revoked["state"] = "revoked"
        keys.append(revoked)
    if not matched:
        raise ValueError(f"publisher key is unknown: {key_id}")
    candidate: dict[str, object] = {
        "schemaVersion": "v2",
        "keys": sorted(keys, key=lambda key: str(key["id"])),
    }
    validate_update_bootstrap_trust_store(candidate)
    return candidate


def encode_update_bootstrap_trust_store(document: object) -> bytes:
    validate_update_bootstrap_trust_store(document)
    return (
        json.dumps(document, indent=2, sort_keys=True, separators=(",", ": "))
        + "\n"
    ).encode("utf-8")


def require_active_publisher_key(
    document: object,
    *,
    key_id: str,
) -> bytes:
    validate_update_bootstrap_trust_store(document)
    if not IDENTIFIER.fullmatch(key_id):
        raise ValueError("publisher key id is invalid")
    if not isinstance(document, dict) or not isinstance(document["keys"], list):
        raise ValueError("trust store contract was not preserved after validation")
    for key in document["keys"]:
        if key["id"] != key_id:
            continue
        if key["state"] == "revoked":
            raise ValueError(f"publisher key is revoked: {key_id}")
        return base64.b64decode(str(key["publicKey"]), validate=True)
    raise ValueError(f"publisher key is unknown: {key_id}")


def require_exact_keys(
    document: dict[object, object],
    expected: set[str],
    location: str,
) -> None:
    actual = set(document)
    unknown = sorted(str(key) for key in actual - expected)
    missing = sorted(expected - actual)
    if unknown:
        raise ValueError(f"{location} contains unknown fields: {', '.join(unknown)}")
    if missing:
        raise ValueError(f"{location} is missing fields: {', '.join(missing)}")
