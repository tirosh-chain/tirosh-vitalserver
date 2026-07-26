from __future__ import annotations

from tirosh_vitalserver.devtools.core.macos_release.package_install import (
    NumericPackageVersion,
    PackageInstallIntent,
    classify_package_install_intent,
)


def version(value: str) -> NumericPackageVersion:
    parsed = NumericPackageVersion.parse(value)
    assert parsed is not None
    return parsed


def test_package_install_intent_classifies_fresh_repair_upgrade_and_downgrade() -> None:
    target = version("0.2.1")

    assert classify_package_install_intent(None, target) is PackageInstallIntent.FRESH
    assert (
        classify_package_install_intent(version("0.2.1"), target)
        is PackageInstallIntent.SAME_VERSION_REPAIR
    )
    assert (
        classify_package_install_intent(version("0.2.0"), target)
        is PackageInstallIntent.UPGRADE
    )
    assert (
        classify_package_install_intent(version("0.2.2"), target)
        is PackageInstallIntent.DOWNGRADE
    )


def test_numeric_package_version_is_strict_and_compares_arbitrary_size_components() -> (
    None
):
    for invalid in ("", "0..2", "0.2.1-dev", " 0.2.1", "1.٢"):
        assert NumericPackageVersion.parse(invalid) is None

    assert NumericPackageVersion.parse("0.2.1") is not None
    assert (
        classify_package_install_intent(
            version(f"{'9' * 5_000}.0"),
            version(f"1{'0' * 5_000}.0"),
        )
        is PackageInstallIntent.UPGRADE
    )
    assert (
        classify_package_install_intent(version("1.0.0"), version("1"))
        is PackageInstallIntent.SAME_VERSION_REPAIR
    )
