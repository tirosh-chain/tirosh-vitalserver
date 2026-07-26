from __future__ import annotations

import subprocess
from collections.abc import Callable, Sequence

from tirosh_vitalserver.devtools.adapters.macos_release.package_receipts import (
    read_package_receipt,
)
from tirosh_vitalserver.devtools.core.macos_release.package_install import (
    PackageReceiptAbsent,
    PackageReceiptPresent,
    PackageReceiptReadFailed,
    PackageReceiptReadStage,
)

IDENTIFIER = "ai.tirosh.vitalserver.helper"


def completed(
    command: Sequence[str],
    *,
    returncode: int = 0,
    stdout: bytes = b"",
    stderr: bytes = b"",
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.CompletedProcess(
        args=list(command),
        returncode=returncode,
        stdout=stdout,
        stderr=stderr,
    )


def package_info_plist(
    *,
    identifier: str = IDENTIFIER,
    version: str = "0.2.1",
    additional_entries: bytes = b"",
) -> bytes:
    return b"".join(
        [
            b'<?xml version="1.0" encoding="UTF-8"?>',
            b'<plist version="1.0"><dict>',
            b"<key>pkgid</key><string>",
            identifier.encode(),
            b"</string>",
            b"<key>pkg-version</key><string>",
            version.encode(),
            b"</string>",
            additional_entries,
            b"</dict></plist>",
        ]
    )


def runner(
    catalog: subprocess.CompletedProcess[bytes],
    info: subprocess.CompletedProcess[bytes] | None = None,
) -> tuple[
    Callable[[Sequence[str]], subprocess.CompletedProcess[bytes]],
    list[list[str]],
]:
    commands: list[list[str]] = []

    def run(command: Sequence[str]) -> subprocess.CompletedProcess[bytes]:
        command = list(command)
        commands.append(command)
        if command == ["/usr/sbin/pkgutil", "--pkgs"]:
            return catalog
        if command == ["/usr/sbin/pkgutil", "--pkg-info-plist", IDENTIFIER]:
            assert info is not None
            return info
        raise AssertionError(f"unexpected command: {command}")

    return run, commands


def test_exact_catalog_membership_and_strict_plist_report_present_version() -> None:
    run, commands = runner(
        completed([], stdout=f"{IDENTIFIER}\n".encode()),
        completed([], stdout=package_info_plist()),
    )

    observation = read_package_receipt(IDENTIFIER, run_process=run)

    assert isinstance(observation, PackageReceiptPresent)
    assert observation.identifier == IDENTIFIER
    assert observation.version.raw_value == "0.2.1"
    assert commands == [
        ["/usr/sbin/pkgutil", "--pkgs"],
        ["/usr/sbin/pkgutil", "--pkg-info-plist", IDENTIFIER],
    ]


def test_similar_catalog_identifier_is_absent_without_info_read() -> None:
    run, commands = runner(
        completed([], stdout=f"{IDENTIFIER}.tools\n".encode()),
    )

    observation = read_package_receipt(IDENTIFIER, run_process=run)

    assert observation == PackageReceiptAbsent(identifier=IDENTIFIER)
    assert commands == [["/usr/sbin/pkgutil", "--pkgs"]]


def test_catalog_failure_with_no_receipt_text_remains_read_failed() -> None:
    run, _ = runner(
        completed(
            [],
            returncode=1,
            stderr=f"No receipt for '{IDENTIFIER}' found at '/'.\n".encode(),
        ),
    )

    observation = read_package_receipt(IDENTIFIER, run_process=run)

    assert isinstance(observation, PackageReceiptReadFailed)
    assert observation.stage is PackageReceiptReadStage.CATALOG
    assert "No receipt" in observation.reason


def test_duplicate_catalog_identifier_is_read_failed() -> None:
    run, _ = runner(
        completed([], stdout=f"{IDENTIFIER}\n{IDENTIFIER}\n".encode()),
    )

    observation = read_package_receipt(IDENTIFIER, run_process=run)

    assert observation == PackageReceiptReadFailed(
        identifier=IDENTIFIER,
        stage=PackageReceiptReadStage.CATALOG,
        reason=f"duplicate package-id value={IDENTIFIER}",
    )


def test_info_plist_mismatch_malformed_version_and_duplicate_keys_are_read_failed() -> (
    None
):
    cases = [
        (
            package_info_plist(identifier="example.other"),
            "identifier mismatch",
        ),
        (
            package_info_plist(version="0.2.1-dev"),
            "version is invalid",
        ),
        (
            package_info_plist(
                additional_entries=(
                    b"<key>pkgid</key><string>ai.tirosh.vitalserver.helper</string>"
                )
            ),
            "duplicate key=pkgid",
        ),
        (
            package_info_plist(
                additional_entries=(b"<key>pkg-version</key><string>0.2.1</string>")
            ),
            "duplicate key=pkg-version",
        ),
    ]

    for plist, expected_reason in cases:
        run, _ = runner(
            completed([], stdout=f"{IDENTIFIER}\n".encode()),
            completed([], stdout=plist),
        )

        observation = read_package_receipt(IDENTIFIER, run_process=run)

        assert isinstance(observation, PackageReceiptReadFailed)
        assert observation.stage is PackageReceiptReadStage.INFO
        assert expected_reason in observation.reason
