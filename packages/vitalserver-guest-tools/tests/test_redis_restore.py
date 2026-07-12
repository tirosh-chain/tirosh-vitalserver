from __future__ import annotations

import subprocess
import tarfile
from pathlib import Path
from typing import Any

import pytest

from tirosh_guest_tools.application import redis_restore
from tirosh_guest_tools.domain.errors import GuestContractError


def test_restore_redis_archive_replaces_volume_without_request_result_files(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    mount_point = tmp_path / "mnt"
    archive = mount_point / "backups" / "redis" / "redis.tar.gz"
    volume = tmp_path / "volume"
    archive.parent.mkdir(parents=True)
    volume.mkdir()
    (volume / "old.rdb").write_text("old", encoding="utf-8")
    source = tmp_path / "archive-source"
    source.mkdir()
    (source / "dump.rdb").write_text("new", encoding="utf-8")
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(source / "dump.rdb", arcname="dump.rdb")
    monkeypatch.setattr(redis_restore, "MOUNT_POINT", mount_point)
    monkeypatch.setattr(redis_restore, "mount_runtime_share", lambda: None)
    clock_syncs: list[str] = []
    monkeypatch.setattr(
        redis_restore,
        "sync_clock",
        lambda _: clock_syncs.append("sync-clock"),
    )
    monkeypatch.setattr(redis_restore, "default_bootstrap_context", lambda: object())
    commands: list[list[str]] = []
    monkeypatch.setattr(
        redis_restore,
        "run",
        lambda args: _record(commands, args),
    )
    monkeypatch.setattr(
        redis_restore,
        "output",
        lambda args: str(volume),
    )

    outcome = redis_restore.restore_redis_archive(archive)

    assert (volume / "dump.rdb").read_text(encoding="utf-8") == "new"
    assert clock_syncs == ["sync-clock"]
    assert not (volume / "old.rdb").exists()
    assert outcome.restored_archive == archive
    assert commands[0][-1] == "stop"
    assert commands[1][-5:] == ["up", "--pull", "never", "--no-build", "-d"]


def test_redis_restore_rejects_unsafe_archive_member(tmp_path: Path) -> None:
    archive = tmp_path / "unsafe.tar.gz"
    source = tmp_path / "source"
    source.mkdir()
    (source / "dump.rdb").write_text("new", encoding="utf-8")
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(source / "dump.rdb", arcname="../dump.rdb")

    with pytest.raises(GuestContractError) as raised:
        redis_restore.validate_archive_members(archive)

    assert raised.value.code == "redis-restore-archive-member-path-unsafe"


def _record(
    commands: list[list[str]],
    args: list[str],
    request_exists_at_command: list[bool] | None = None,
    request: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    commands.append(args)
    if request_exists_at_command is not None and request is not None:
        request_exists_at_command.append(request.exists())
    return subprocess.CompletedProcess(args, 0, "", "")
