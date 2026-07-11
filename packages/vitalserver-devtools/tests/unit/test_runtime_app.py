from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.adapters.macos_release import runtime_app


def test_app_bundle_contains_and_signs_headless_platform_agent(
    tmp_path: Path,
    monkeypatch,
) -> None:
    root = tmp_path / "repo"
    runtime_dir = root / "apps/vitalserver-macos-runtime"
    app_assets = runtime_dir / "Support/App"
    app_assets.mkdir(parents=True)
    (app_assets / runtime_app.APP_INFO_PLIST_NAME).write_text(
        "<plist><dict/></plist>",
        encoding="utf-8",
    )
    (app_assets / runtime_app.APP_ICON_NAME).write_bytes(b"icon")
    (app_assets / runtime_app.APP_BRAND_IMAGE_NAME).write_bytes(b"brand")
    pwa_dist = root / runtime_app.PWA_APP_DIR / runtime_app.PWA_DIST_DIR
    pwa_dist.mkdir(parents=True)
    (pwa_dist / "index.html").write_text("<html></html>", encoding="utf-8")

    release_dir = runtime_dir / ".build/release"
    release_dir.mkdir(parents=True)
    helper = release_dir / "VitalServerHelper"
    helper.write_bytes(b"helper")
    platform_agent = release_dir / runtime_app.PLATFORM_AGENT_PRODUCT_NAME
    platform_agent.write_bytes(b"agent")

    commands: list[list[str]] = []
    monkeypatch.setattr(
        runtime_app,
        "run",
        lambda command, **_: commands.append([str(part) for part in command]),
    )
    app_bundle = root / "dist/VitalServer Helper.app"

    runtime_app.build_app_bundle(
        root=root,
        runtime_dir=runtime_dir,
        helper_bin=helper,
        app_bundle=app_bundle,
        app_name="VitalServer Helper",
        helper_version="2.0.0",
        codesign_identity="-",
    )

    bundled_agent = (
        app_bundle / "Contents/MacOS" / runtime_app.PLATFORM_AGENT_PRODUCT_NAME
    )
    assert bundled_agent.read_bytes() == b"agent"
    assert (app_bundle / "Contents/Resources/runtime-control-pwa/index.html").is_file()
    assert [
        "codesign",
        "--force",
        "--sign",
        "-",
        str(bundled_agent),
    ] in commands
    assert commands[-1] == [
        "codesign",
        "--force",
        "--sign",
        "-",
        str(app_bundle),
    ]
