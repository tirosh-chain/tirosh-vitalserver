from __future__ import annotations

import hashlib
import io
import os
import subprocess
import tarfile
from collections.abc import Callable
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import BinaryIO

from tirosh_guest_tools.application.guest_control.update_owner_worker import (
    UpdateArtifactUnavailable,
    UpdateEffectFailed,
)
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.guest_runtime_release import (
    GuestRuntimeRelease,
    GuestRuntimeReleaseOperation,
)

UPDATE_ARTIFACT_KINDS = frozenset({"container-image-set", "guest-runtime-release"})


class ImmutableUpdateArtifactStore:
    """Guest-owned, content-addressed archive import and verification boundary."""

    def __init__(self, root: Path) -> None:
        self._root = root

    def import_bytes(self, *, kind: str, digest: str, content: bytes) -> str:
        return self.import_stream(
            kind=kind,
            digest=digest,
            stream=io.BytesIO(content),
            size_bytes=len(content),
        )

    def import_stream(
        self,
        *,
        kind: str,
        digest: str,
        stream: BinaryIO,
        size_bytes: int,
    ) -> str:
        digest_hex = _validated_digest(kind, digest)
        if size_bytes < 1:
            raise UpdateArtifactUnavailable("Update archive is empty.")
        directory = self._directory(kind)
        directory.mkdir(parents=True, exist_ok=True)
        destination = directory / f"{digest_hex}.archive"
        if destination.exists():
            self._verify(destination, digest_hex)
            return f"{kind}/{destination.name}"
        temporary: Path | None = None
        try:
            with NamedTemporaryFile(
                dir=directory, prefix=".import-", delete=False
            ) as file:
                temporary = Path(file.name)
                observed = hashlib.sha256()
                remaining = size_bytes
                while remaining:
                    chunk = stream.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise UpdateArtifactUnavailable(
                            "Update archive ended before its declared Content-Length."
                        )
                    file.write(chunk)
                    observed.update(chunk)
                    remaining -= len(chunk)
                actual = observed.hexdigest()
                if actual != digest_hex:
                    raise UpdateArtifactUnavailable(
                        "Update archive digest mismatch "
                        f"expected={digest_hex} actual={actual}."
                    )
                file.flush()
                os.fsync(file.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, destination)
            self._verify(destination, digest_hex)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        return f"{kind}/{destination.name}"

    def resolve(self, *, kind: str, digest: str) -> Path:
        digest_hex = _validated_digest(kind, digest)
        archive = self._directory(kind) / f"{digest_hex}.archive"
        if not archive.is_file():
            raise UpdateArtifactUnavailable(
                f"Guest-owned update archive is missing: kind={kind} digest={digest}."
            )
        self._verify(archive, digest_hex)
        return archive

    def _directory(self, kind: str) -> Path:
        if kind not in UPDATE_ARTIFACT_KINDS:
            raise UpdateArtifactUnavailable(
                f"Update artifact kind is unsupported: {kind}."
            )
        return self._root / kind

    @staticmethod
    def _verify(path: Path, expected: str) -> None:
        digest = hashlib.sha256()
        try:
            with path.open("rb") as file:
                for chunk in iter(lambda: file.read(1024 * 1024), b""):
                    digest.update(chunk)
        except OSError as error:
            raise UpdateArtifactUnavailable(
                f"Update archive read failed: path={path} reason={error}."
            ) from error
        actual = digest.hexdigest()
        if actual != expected:
            raise UpdateArtifactUnavailable(
                f"Guest-owned update archive digest mismatch "
                f"expected={expected} actual={actual}."
            )


class DockerComposeContainerImageSetEffect:
    def __init__(self, reconcile: Callable[[], None]) -> None:
        self._reconcile = reconcile

    def reconcile(self, archive: Path) -> None:
        try:
            result = subprocess.run(
                ["docker", "image", "load", "--input", str(archive)],
                check=False,
                capture_output=True,
                text=True,
            )
        except OSError as error:
            raise UpdateEffectFailed(
                f"Docker image load could not start: {error}."
            ) from error
        if result.returncode != 0:
            detail = result.stderr.strip() or "no stderr"
            raise UpdateEffectFailed(
                f"Docker image load failed exit={result.returncode}: {detail}."
            )
        self._reconcile()


class SystemdUpdateOwnerWorkerDispatcher:
    def request_work(self) -> None:
        try:
            result = subprocess.run(
                [
                    "systemctl",
                    "start",
                    "--no-block",
                    RuntimeService.UPDATE_OWNER_WORKER.value,
                ],
                check=False,
                capture_output=True,
                text=True,
            )
        except OSError as error:
            raise GuestControlDependencyError(
                f"Guest update owner worker dispatch could not start: {error}.",
                kind="updateOwnerWorkerUnavailable",
            ) from error
        if result.returncode != 0:
            detail = result.stderr.strip() or "no stderr"
            raise GuestControlDependencyError(
                "Guest update owner worker dispatch failed "
                f"exit={result.returncode}: {detail}.",
                kind="updateOwnerWorkerUnavailable",
            )


class AtomicGuestRuntimeReleaseEffect:
    """Stages one immutable release and switches its active link atomically."""

    def __init__(
        self,
        *,
        releases_root: Path,
        active_link: Path,
        reconcile: Callable[[], None],
    ) -> None:
        self._releases_root = releases_root
        self._active_link = active_link
        self._reconcile = reconcile

    def provision_initial(
        self,
        release: GuestRuntimeRelease,
        archive: Path,
    ) -> None:
        """Replace the bootstrap directory with the first immutable release link."""

        destination = self._releases_root / release.identity
        if self._active_link.is_symlink():
            self._require_slot_digest(destination, release.digest)
            if self._active_link.resolve(strict=True) != destination.resolve():
                raise UpdateEffectFailed(
                    "Initial Guest Runtime active link targets another release."
                )
            return
        if not self._active_link.is_dir():
            raise UpdateEffectFailed(
                "Initial Guest Runtime directory is unavailable: "
                f"{self._active_link}."
            )
        staging = self._releases_root / f".{release.identity}.initial.staging"
        previous = self._releases_root / f".{release.identity}.bootstrap.previous"
        self._releases_root.mkdir(parents=True, exist_ok=True)
        _remove_tree(staging)
        _remove_tree(previous)
        staging.mkdir(mode=0o700)
        try:
            self._safe_extract(archive, staging)
            (staging / ".artifact-sha256").write_text(
                release.digest + "\n",
                encoding="utf-8",
            )
            if destination.exists():
                self._require_slot_digest(destination, release.digest)
                _remove_tree(staging)
            else:
                os.replace(staging, destination)
            os.replace(self._active_link, previous)
            self._switch_active(destination)
            _remove_tree(previous)
        except Exception:
            if self._active_link.is_symlink():
                self._active_link.unlink()
            if previous.exists():
                os.replace(previous, self._active_link)
            _remove_tree(staging)
            raise

    def activate(
        self,
        operation: GuestRuntimeReleaseOperation,
        archive: Path,
    ) -> None:
        identity = operation.target.identity
        destination = self._releases_root / identity
        staging = self._releases_root / f".{identity}.{operation.operation_id}.staging"
        self._releases_root.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            self._require_slot_digest(destination, operation.target.digest)
            previous = self._read_active_target()
            self._switch_active(destination)
            try:
                self._reconcile()
            except Exception:
                self._restore_active(previous)
                raise
            return
        staging.mkdir(mode=0o700)
        previous = self._read_active_target()
        try:
            self._safe_extract(archive, staging)
            (staging / ".artifact-sha256").write_text(
                operation.target.digest + "\n",
                encoding="utf-8",
            )
            os.replace(staging, destination)
            self._switch_active(destination)
            try:
                self._reconcile()
            except Exception:
                self._restore_active(previous)
                raise
        except Exception:
            _remove_tree(staging)
            raise

    def _safe_extract(self, archive: Path, destination: Path) -> None:
        try:
            with tarfile.open(archive, "r:*") as package:
                for member in package.getmembers():
                    member_path = Path(member.name)
                    if (
                        member_path.is_absolute()
                        or ".." in member_path.parts
                        or member.issym()
                        or member.islnk()
                        or member.isdev()
                    ):
                        raise UpdateEffectFailed(
                            f"Guest Runtime archive member is unsafe: {member.name}."
                        )
                package.extractall(destination, filter="data")
        except (tarfile.TarError, OSError) as error:
            raise UpdateEffectFailed(
                f"Guest Runtime archive extraction failed: {error}."
            ) from error

    def _read_active_target(self) -> Path | None:
        if not self._active_link.exists() and not self._active_link.is_symlink():
            return None
        if not self._active_link.is_symlink():
            raise UpdateEffectFailed(
                "Guest Runtime active path is not a symbolic link: "
                f"{self._active_link}."
            )
        return self._active_link.resolve(strict=True)

    @staticmethod
    def _require_slot_digest(destination: Path, expected: str) -> None:
        marker = destination / ".artifact-sha256"
        try:
            actual = marker.read_text(encoding="utf-8").strip()
        except OSError as error:
            raise UpdateEffectFailed(
                f"Guest Runtime release slot digest is unavailable: {error}."
            ) from error
        if actual != expected:
            raise UpdateEffectFailed(
                "Guest Runtime release slot digest mismatch "
                f"expected={expected} actual={actual}."
            )

    def _switch_active(self, destination: Path) -> None:
        temporary = self._active_link.with_name(
            f".{self._active_link.name}.next-{os.getpid()}"
        )
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(destination)
        os.replace(temporary, self._active_link)

    def _restore_active(self, previous: Path | None) -> None:
        if previous is None:
            self._active_link.unlink(missing_ok=True)
            return
        self._switch_active(previous)


def _validated_digest(kind: str, digest: str) -> str:
    if kind not in UPDATE_ARTIFACT_KINDS:
        raise UpdateArtifactUnavailable(f"Update artifact kind is unsupported: {kind}.")
    if not digest.startswith("sha256:"):
        raise UpdateArtifactUnavailable("Update artifact digest must use sha256:<hex>.")
    digest_hex = digest.removeprefix("sha256:")
    if len(digest_hex) != 64 or any(
        value not in "0123456789abcdef" for value in digest_hex
    ):
        raise UpdateArtifactUnavailable(
            "Update artifact digest must contain 64 lowercase hexadecimal characters."
        )
    return digest_hex


def _remove_tree(path: Path) -> None:
    if not path.exists():
        return
    for child in path.iterdir():
        if child.is_dir() and not child.is_symlink():
            _remove_tree(child)
        else:
            child.unlink()
    path.rmdir()
