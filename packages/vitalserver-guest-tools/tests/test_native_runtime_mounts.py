from pathlib import Path

from tirosh_guest_tools.infrastructure import common
from tirosh_guest_tools.infrastructure.settings import ShareMountMode


def test_native_share_is_an_explicit_directory_without_mount_probe(
    tmp_path: Path,
    monkeypatch,
) -> None:
    probes: list[Path] = []
    monkeypatch.setattr(common, "is_mountpoint", lambda path: probes.append(path))

    target = tmp_path / "runtime"
    common.mount_share("unused-native-tag", target, ShareMountMode.NATIVE)

    assert target.is_dir()
    assert probes == []


def test_virtiofs_share_keeps_explicit_mount_effect(
    tmp_path: Path,
    monkeypatch,
) -> None:
    commands: list[list[str]] = []
    monkeypatch.setattr(common, "is_mountpoint", lambda _path: False)
    monkeypatch.setattr(
        common.subprocess,
        "run",
        lambda command, check: commands.append(command),
    )

    target = tmp_path / "runtime"
    common.mount_share("runtime-tag", target, ShareMountMode.VIRTIOFS)

    assert commands == [["mount", "-t", "virtiofs", "runtime-tag", str(target)]]
