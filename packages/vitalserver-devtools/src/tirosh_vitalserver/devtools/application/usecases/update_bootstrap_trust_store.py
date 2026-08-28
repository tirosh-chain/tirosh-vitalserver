from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.update_bootstrap_trust_store import (
    create_update_bootstrap_trust_store,
    encode_update_bootstrap_trust_store,
    publisher_key_document,
    revoke_update_bootstrap_publisher_key,
    rotate_update_bootstrap_trust_store,
)


@dataclass(frozen=True)
class UpdateBootstrapTrustStoreOperations:
    read_store: Callable[[Path], object]
    read_ed25519_public_key: Callable[[Path], bytes]
    write_new_store: Callable[[Path, bytes], None]


def create(
    *,
    publisher_key_id: str,
    publisher_public_key: Path,
    output: Path,
    operations: UpdateBootstrapTrustStoreOperations,
) -> int:
    try:
        key = publisher_key_document(
            key_id=publisher_key_id,
            public_key=operations.read_ed25519_public_key(publisher_public_key),
        )
        document = create_update_bootstrap_trust_store(key)
    except ValueError as error:
        raise DomainError(f"trust store create rejected: {error}") from error
    operations.write_new_store(
        output,
        encode_update_bootstrap_trust_store(document),
    )
    return 0


def rotate(
    *,
    trust_store: Path,
    publisher_key_id: str,
    publisher_public_key: Path,
    output: Path,
    operations: UpdateBootstrapTrustStoreOperations,
) -> int:
    try:
        key = publisher_key_document(
            key_id=publisher_key_id,
            public_key=operations.read_ed25519_public_key(publisher_public_key),
        )
        document = rotate_update_bootstrap_trust_store(
            operations.read_store(trust_store),
            key,
        )
    except ValueError as error:
        raise DomainError(f"trust store rotation rejected: {error}") from error
    operations.write_new_store(
        output,
        encode_update_bootstrap_trust_store(document),
    )
    return 0


def revoke(
    *,
    trust_store: Path,
    publisher_key_id: str,
    output: Path,
    operations: UpdateBootstrapTrustStoreOperations,
) -> int:
    try:
        document = revoke_update_bootstrap_publisher_key(
            operations.read_store(trust_store),
            key_id=publisher_key_id,
        )
    except ValueError as error:
        raise DomainError(f"trust store revocation rejected: {error}") from error
    operations.write_new_store(
        output,
        encode_update_bootstrap_trust_store(document),
    )
    return 0
