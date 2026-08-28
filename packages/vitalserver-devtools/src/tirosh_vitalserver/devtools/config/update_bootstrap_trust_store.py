from __future__ import annotations

import json
import stat
from pathlib import Path

from tirosh_vitalserver.devtools.core.update_bootstrap_trust_store import (
    validate_update_bootstrap_trust_store,
)


class UpdateBootstrapTrustStoreError(Exception):
    pass


class UpdateBootstrapTrustStoreUnavailableError(UpdateBootstrapTrustStoreError):
    pass


class UpdateBootstrapTrustStoreReadError(UpdateBootstrapTrustStoreError):
    pass


class UpdateBootstrapTrustStoreDecodeError(UpdateBootstrapTrustStoreError):
    pass


class UpdateBootstrapTrustStoreInvalidError(UpdateBootstrapTrustStoreError):
    pass


def load_update_bootstrap_trust_store(path: Path) -> Path:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as error:
        raise UpdateBootstrapTrustStoreUnavailableError(
            f"update bootstrap trust store is unavailable: {path}"
        ) from error
    except OSError as error:
        raise UpdateBootstrapTrustStoreReadError(
            f"update bootstrap trust store inspection failed {path}: {error}"
        ) from error
    if stat.S_ISLNK(mode):
        raise UpdateBootstrapTrustStoreInvalidError(
            f"update bootstrap trust store must not be a symlink: {path}"
        )
    if not stat.S_ISREG(mode):
        raise UpdateBootstrapTrustStoreInvalidError(
            f"update bootstrap trust store must be a regular file: {path}"
        )
    try:
        encoded = path.read_bytes()
    except OSError as error:
        raise UpdateBootstrapTrustStoreReadError(
            "update bootstrap trust store read failed "
            f"{path}: {error}"
        ) from error
    try:
        document = json.loads(encoded.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise UpdateBootstrapTrustStoreDecodeError(
            "update bootstrap trust store decode failed "
            f"{path}: {error}"
        ) from error
    try:
        validate_update_bootstrap_trust_store(document)
    except ValueError as error:
        raise UpdateBootstrapTrustStoreInvalidError(
            f"update bootstrap trust store is invalid {path}: {error}"
        ) from error
    return path
