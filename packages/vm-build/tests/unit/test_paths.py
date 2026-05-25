from __future__ import annotations

from tirosh_vitalserver.vm_build.toolchain.workspace_paths import repo_root


def test_repo_root_resolves_workspace_root() -> None:
    root = repo_root()

    assert (root / "apps").is_dir()
    assert (root / "packages" / "vm-build").is_dir()
