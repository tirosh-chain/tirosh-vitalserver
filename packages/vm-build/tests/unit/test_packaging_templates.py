from __future__ import annotations

import os
from argparse import Namespace

from tirosh_vitalserver.vm_build.paths import repo_root
from tirosh_vitalserver.vm_build.release import (
    load_release_settings,
    render_packaging_executable,
    render_packaging_template,
    settings_install_app_bundle,
)


def test_packaging_templates_render_from_build_config(tmp_path) -> None:
    root = repo_root()
    settings = load_release_settings(
        Namespace(
            config=root
            / "apps/vitalserver-macos-runtime/Support/Build/vm-build.toml",
        ),
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
    assert "${PRODUCT_ROOT}" not in rendered
    assert "/Library/Application Support/TiroshVitalServer" in rendered
    assert "Applications/VitalServer Helper.app" in components.read_text(
        encoding="utf-8"
    )
    assert os.access(postinstall, os.X_OK)
    assert os.access(proxy_run, os.X_OK)
    assert os.access(uninstall, os.X_OK)
