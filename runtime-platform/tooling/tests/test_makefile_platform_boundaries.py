"""Focused tests for portable and native Make target boundaries."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


RUNTIME_PLATFORM_ROOT = Path(__file__).resolve().parents[2]
MACOS_PROVIDER_COMMAND = (
    "platform-specific-swift test --package-path providers/macos-virtualization"
)


def make_plan(target: str) -> str:
    result = subprocess.run(
        ["make", "-n", target, "SWIFT=platform-specific-swift"],
        cwd=RUNTIME_PLATFORM_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


class MakefilePlatformBoundaryTests(unittest.TestCase):
    def test_portable_check_does_not_compile_the_macos_provider(self) -> None:
        self.assertNotIn(MACOS_PROVIDER_COMMAND, make_plan("check"))

    def test_macos_provider_target_keeps_native_compilation_explicit(self) -> None:
        self.assertIn(MACOS_PROVIDER_COMMAND, make_plan("macos-provider-test"))

