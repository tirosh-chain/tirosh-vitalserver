from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.runtime_settings import (
    RuntimeSettingsContractError,
    validated_runtime_settings,
)


class FileRuntimeSettingsRepository:
    def __init__(self, path: Path) -> None:
        self._path = path

    def read(self) -> dict[str, Any]:
        try:
            data = self._path.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise GuestControlDependencyError(
                f"runtime settings file is missing: {self._path}",
                kind="runtimeSettingsMissing",
            ) from error
        except OSError as error:
            raise GuestControlDependencyError(
                f"runtime settings read failed path={self._path}: {error}",
                kind="runtimeSettingsReadFailed",
            ) from error
        try:
            value = json.loads(data)
        except json.JSONDecodeError as error:
            raise GuestControlDependencyError(
                f"runtime settings JSON is invalid path={self._path}: {error}",
                kind="runtimeSettingsInvalid",
            ) from error
        if not isinstance(value, dict):
            raise GuestControlDependencyError(
                f"runtime settings document is not an object: {self._path}",
                kind="runtimeSettingsInvalid",
            )
        try:
            return validated_runtime_settings(value)
        except RuntimeSettingsContractError as error:
            raise GuestControlDependencyError(
                str(error), kind="runtimeSettingsInvalid"
            ) from error

    def save(self, settings: dict[str, Any]) -> None:
        validated = validated_runtime_settings(settings)
        temporary: str | None = None
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary = tempfile.mkstemp(
                dir=self._path.parent,
                prefix=f".{self._path.name}.",
                suffix=".tmp",
            )
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump(validated, stream, indent=2, sort_keys=True)
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
                f"runtime settings write failed path={self._path}: {error}",
                kind="runtimeSettingsWriteFailed",
            ) from error
