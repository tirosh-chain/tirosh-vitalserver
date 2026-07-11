from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.runtime_admin import validated_admin_password


class FileRuntimeAdminRepository:
    def __init__(self, runtime_config_path: Path) -> None:
        self._path = runtime_config_path

    def replace_admin_password(self, password: str) -> None:
        validated = validated_admin_password(password)
        document = self._read_config()
        document["adminPassword"] = validated
        temporary: str | None = None
        try:
            descriptor, temporary = tempfile.mkstemp(
                dir=self._path.parent,
                prefix=f".{self._path.name}.",
                suffix=".tmp",
            )
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump(document, stream, indent=2, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, self._path)
        except OSError as error:
            if temporary is not None:
                try:
                    os.unlink(temporary)
                except FileNotFoundError:
                    pass
            raise GuestControlDependencyError(
                f"runtime admin password write failed path={self._path}: {error}",
                kind="runtimeAdminPasswordWriteFailed",
            ) from error

    def _read_config(self) -> dict[str, Any]:
        try:
            text = self._path.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise GuestControlDependencyError(
                f"runtime config file is missing: {self._path}",
                kind="runtimeConfigMissing",
            ) from error
        except OSError as error:
            raise GuestControlDependencyError(
                f"runtime config read failed path={self._path}: {error}",
                kind="runtimeConfigReadFailed",
            ) from error
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise GuestControlDependencyError(
                f"runtime config JSON is invalid path={self._path}: {error}",
                kind="runtimeConfigInvalid",
            ) from error
        if not isinstance(document, dict):
            raise GuestControlDependencyError(
                f"runtime config document is not an object: {self._path}",
                kind="runtimeConfigInvalid",
            )
        if not isinstance(document.get("adminPassword"), str):
            raise GuestControlDependencyError(
                f"runtime config adminPassword field is invalid: {self._path}",
                kind="runtimeConfigInvalid",
            )
        return document
