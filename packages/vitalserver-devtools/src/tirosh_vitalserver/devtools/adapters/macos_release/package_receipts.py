from __future__ import annotations

import plistlib
import subprocess
import xml.etree.ElementTree as element_tree
from collections.abc import Callable, Sequence

from tirosh_vitalserver.devtools.core.macos_release.package_install import (
    NumericPackageVersion,
    PackageReceiptAbsent,
    PackageReceiptObservation,
    PackageReceiptPresent,
    PackageReceiptReadFailed,
    PackageReceiptReadStage,
)

RunProcess = Callable[
    [Sequence[str]],
    subprocess.CompletedProcess[bytes],
]


def read_package_receipt(
    identifier: str,
    *,
    run_process: RunProcess | None = None,
) -> PackageReceiptObservation:
    execute = run_process or _run_process
    catalog_command = ["/usr/sbin/pkgutil", "--pkgs"]
    try:
        catalog_result = execute(catalog_command)
    except OSError as error:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.CATALOG,
            reason=f"command execution failed: {error}",
        )
    if catalog_result.returncode != 0:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.CATALOG,
            reason=_process_failure_reason(catalog_result),
        )
    catalog = _decode_utf8(catalog_result.stdout)
    if catalog is None:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.CATALOG,
            reason="stdout is not valid UTF-8",
        )

    matching_identifiers = [
        candidate for candidate in catalog.splitlines() if candidate == identifier
    ]
    if len(matching_identifiers) > 1:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.CATALOG,
            reason=f"duplicate package-id value={identifier}",
        )
    if not matching_identifiers:
        return PackageReceiptAbsent(identifier=identifier)

    info_command = ["/usr/sbin/pkgutil", "--pkg-info-plist", identifier]
    try:
        info_result = execute(info_command)
    except OSError as error:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason=f"command execution failed: {error}",
        )
    if info_result.returncode != 0:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason=_process_failure_reason(info_result),
        )
    if not isinstance(info_result.stdout, bytes):
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason="stdout type is not bytes",
        )

    duplicate_key = _first_duplicate_required_key(info_result.stdout)
    if duplicate_key is not None:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason=f"duplicate key={duplicate_key}",
        )
    try:
        document = plistlib.loads(info_result.stdout)
    except (plistlib.InvalidFileException, ValueError, TypeError) as error:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason=f"plist decode failed: {error}",
        )
    if not isinstance(document, dict):
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason="plist root is not a dictionary",
        )

    actual_identifier = document.get("pkgid")
    if not isinstance(actual_identifier, str) or not actual_identifier:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason="plist pkgid is missing or invalid",
        )
    if actual_identifier != identifier:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason=(
                f"identifier mismatch actual={actual_identifier} expected={identifier}"
            ),
        )

    version_value = document.get("pkg-version")
    if not isinstance(version_value, str) or not version_value:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason="plist pkg-version is missing or invalid",
        )
    version = NumericPackageVersion.parse(version_value)
    if version is None:
        return PackageReceiptReadFailed(
            identifier=identifier,
            stage=PackageReceiptReadStage.INFO,
            reason=f"version is invalid value={version_value}",
        )
    return PackageReceiptPresent(identifier=identifier, version=version)


def _run_process(command: Sequence[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        list(command),
        capture_output=True,
        check=False,
    )


def _decode_utf8(value: object) -> str | None:
    if not isinstance(value, bytes):
        return None
    try:
        return value.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _process_failure_reason(
    result: subprocess.CompletedProcess[bytes],
) -> str:
    parts = [f"exitCode={result.returncode}"]
    stdout = _decode_utf8(result.stdout)
    stderr = _decode_utf8(result.stderr)
    if stdout is None:
        parts.append("stdout=invalid-utf8")
    elif stdout.strip():
        parts.append(f"stdout={stdout.strip()}")
    if stderr is None:
        parts.append("stderr=invalid-utf8")
    elif stderr.strip():
        parts.append(f"stderr={stderr.strip()}")
    return " ".join(parts)


def _first_duplicate_required_key(data: bytes) -> str | None:
    try:
        root = element_tree.fromstring(data)
    except element_tree.ParseError:
        return None
    keys = [
        node.text for node in root.iter("key") if node.text in {"pkgid", "pkg-version"}
    ]
    for key in ("pkgid", "pkg-version"):
        if keys.count(key) > 1:
            return key
    return None
