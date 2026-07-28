from __future__ import annotations

import json
import os
import stat
from contextlib import suppress
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.update_bootstrap_trust_store import (
    require_active_publisher_key,
    validate_update_bootstrap_trust_store,
)


def read_trust_store(path: Path) -> object:
    encoded = read_regular_file(path, "update bootstrap trust store")
    try:
        document = json.loads(encoded.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise DomainError(
            f"update bootstrap trust store decode failed path={path}: {error}"
        ) from error
    try:
        validate_update_bootstrap_trust_store(document)
    except ValueError as error:
        raise DomainError(
            f"update bootstrap trust store is invalid path={path}: {error}"
        ) from error
    return document


def read_ed25519_public_key(path: Path) -> bytes:
    encoded = read_regular_file(path, "publisher public key")
    try:
        public_key = serialization.load_pem_public_key(encoded)
    except (TypeError, ValueError) as error:
        raise DomainError(
            f"publisher public key decode failed path={path}: {error}"
        ) from error
    if not isinstance(public_key, Ed25519PublicKey):
        raise DomainError(
            f"publisher public key must be Ed25519 path={path}"
        )
    return public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )


def read_active_publisher_key(path: Path, key_id: str) -> bytes:
    try:
        return require_active_publisher_key(
            read_trust_store(path),
            key_id=key_id,
        )
    except ValueError as error:
        raise DomainError(
            "update bootstrap publisher trust failed "
            f"path={path} keyId={key_id}: {error}"
        ) from error


def write_new_store(path: Path, encoded: bytes) -> None:
    if not path.parent.is_dir():
        raise DomainError(
            f"trust store output parent is unavailable: {path.parent}"
        )
    descriptor: int | None = None
    try:
        descriptor = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o644,
        )
        with os.fdopen(descriptor, "wb") as output:
            descriptor = None
            output.write(encoded)
            output.flush()
            os.fsync(output.fileno())
    except FileExistsError as error:
        raise DomainError(f"trust store output already exists: {path}") from error
    except OSError as error:
        if descriptor is not None:
            os.close(descriptor)
        with suppress(OSError):
            path.unlink(missing_ok=True)
        raise DomainError(
            f"trust store output write failed path={path}: {error}"
        ) from error


def read_regular_file(path: Path, label: str) -> bytes:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as error:
        raise DomainError(f"{label} is unavailable: {path}") from error
    except OSError as error:
        raise DomainError(f"{label} inspection failed path={path}: {error}") from error
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise DomainError(f"{label} must be a regular file: {path}")
    try:
        return path.read_bytes()
    except OSError as error:
        raise DomainError(f"{label} read failed path={path}: {error}") from error
