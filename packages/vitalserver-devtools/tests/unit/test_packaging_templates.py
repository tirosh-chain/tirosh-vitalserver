from __future__ import annotations

import os
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.macos_release.installer_templates import (
    render_packaging_executable,
    render_packaging_template,
)
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    settings_install_app_bundle,
)


def test_packaging_templates_render_from_build_config(tmp_path: Path) -> None:
    root = repo_root()
    settings = load_macos_release_settings(
        root / "config/vm-build.toml",
        root,
    )
    packaging = root / "apps/vitalserver-macos-runtime/Support/Packaging"

    postinstall = tmp_path / "postinstall"
    proxy_run = tmp_path / "vitalserver-proxy-run"
    uninstall = tmp_path / "tirosh-vitalserver-uninstall"
    components = tmp_path / "components.plist"

    render_packaging_executable(
        settings,
        packaging / "postinstall.template",
        postinstall,
    )
    render_packaging_executable(
        settings,
        packaging / "proxy-run.template",
        proxy_run,
    )
    render_packaging_executable(
        settings,
        packaging / "uninstall.template",
        uninstall,
    )
    render_packaging_template(
        settings,
        packaging / "components.plist.template",
        components,
        {
            "APP_BUNDLE_ROOT_RELATIVE": settings_install_app_bundle(settings).strip(
                "/"
            ),
        },
    )

    rendered = "\n".join(
        path.read_text(encoding="utf-8")
        for path in [postinstall, proxy_run, uninstall, components]
    )
    uninstall_text = uninstall.read_text(encoding="utf-8")
    assert "${PRODUCT_ROOT}" not in rendered
    assert "/Library/Application Support/TiroshVitalServer" in rendered
    assert 'preserve_path "${vm_home}/data/backups/redis"' in uninstall_text
    assert "Applications/VitalServer Helper.app" in components.read_text(
        encoding="utf-8"
    )
    assert os.access(postinstall, os.X_OK)
    assert os.access(proxy_run, os.X_OK)
    assert os.access(uninstall, os.X_OK)
