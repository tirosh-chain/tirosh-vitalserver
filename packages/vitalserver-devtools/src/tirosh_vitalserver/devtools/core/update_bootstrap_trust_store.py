from __future__ import annotations

import base64
import binascii
import re

IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


def validate_update_bootstrap_trust_store(
    document: object,
) -> None:
    if not isinstance(document, dict):
        raise ValueError("trust store must be a JSON object")
    require_exact_keys(document, {"schemaVersion", "keys"}, "trust store")
    if document["schemaVersion"] != "v1":
        raise ValueError("trust store schemaVersion must be v1")
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
            {"id", "algorithm", "publicKey"},
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
        public_key = key["publicKey"]
        if not isinstance(public_key, str):
            raise ValueError(f"{location}.publicKey must be base64 text")
        try:
            decoded = base64.b64decode(public_key, validate=True)
        except (binascii.Error, ValueError) as error:
            raise ValueError(f"{location}.publicKey is not valid base64") from error
        if len(decoded) != 32:
            raise ValueError(f"{location}.publicKey must decode to 32 bytes")


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
