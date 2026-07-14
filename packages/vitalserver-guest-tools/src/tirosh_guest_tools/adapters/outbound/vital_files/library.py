from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError


class FileVitalFileLibrary:
    """Owns atomic writes to the Guest-visible Vital Files library."""

    def __init__(self, root: Path) -> None:
        self._root = root

    def import_files(
        self, files: list[tuple[str, bytes]]
    ) -> list[dict[str, object]]:
        if not files:
            raise GuestControlDependencyError(
                "Select at least one .vital file.",
                kind="vitalFileUploadInvalid",
            )
        if not self._root.is_dir():
            raise GuestControlDependencyError(
                f"Vital Files library is unavailable: {self._root}",
                kind="vitalFileLibraryUnavailable",
            )

        names: set[str] = set()
        for filename, _ in files:
            if (
                not filename
                or Path(filename).name != filename
                or "\\" in filename
                or Path(filename).suffix.lower() != ".vital"
            ):
                display_name = filename or "<missing filename>"
                raise GuestControlDependencyError(
                    f"Only .vital files can be uploaded: {display_name}",
                    kind="vitalFileUploadInvalid",
                )
            if filename in names:
                raise GuestControlDependencyError(
                    f"Upload contains duplicate filenames: {filename}",
                    kind="vitalFileUploadInvalid",
                )
            names.add(filename)
            if (self._root / filename).exists():
                raise GuestControlDependencyError(
                    f"Vital Files library already contains: {filename}",
                    kind="vitalFileUploadConflict",
                )

        staging = Path(tempfile.mkdtemp(prefix=".vital-import-", dir=self._root))
        committed: list[Path] = []
        try:
            for filename, content in files:
                staged = staging / filename
                with staged.open("xb") as output:
                    output.write(content)
                    output.flush()
                    os.fsync(output.fileno())
            for filename, _ in files:
                staged = staging / filename
                destination = self._root / filename
                os.link(staged, destination)
                committed.append(destination)
                staged.unlink()
            staging.rmdir()
        except OSError as error:
            recovery_errors: list[str] = []
            for destination in committed:
                try:
                    destination.unlink(missing_ok=True)
                except OSError as rollback_error:
                    recovery_errors.append(
                        f"rollback {destination.name}: {rollback_error}"
                    )
            try:
                shutil.rmtree(staging)
            except OSError as cleanup_error:
                recovery_errors.append(f"cleanup {staging}: {cleanup_error}")
            recovery_detail = (
                f"; recovery failures: {'; '.join(recovery_errors)}"
                if recovery_errors
                else ""
            )
            raise GuestControlDependencyError(
                f"Vital Files upload failed: {error}{recovery_detail}",
                kind="vitalFileUploadFailed",
            ) from error

        return [
            {
                "fileName": filename,
                "relativePath": filename,
                "sizeBytes": len(content),
            }
            for filename, content in files
        ]
