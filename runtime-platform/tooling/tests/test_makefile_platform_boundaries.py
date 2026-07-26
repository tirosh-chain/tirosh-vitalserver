"""Focused tests for portable and native Make target boundaries."""

from __future__ import annotations

import ast
import subprocess
import unittest
from pathlib import Path


RUNTIME_PLATFORM_ROOT = Path(__file__).resolve().parents[2]
MACOS_PACKAGE_TEST_SOURCE = (
    RUNTIME_PLATFORM_ROOT
    / "tooling"
    / "tests"
    / "test_macos_host_package_composer.py"
)
MACOS_PROVIDER_COMMAND = (
    "platform-specific-swift test --package-path providers/macos-virtualization"
)
MACOS_PACKAGE_TEST = "tooling.tests.test_macos_host_package_composer"
PORTABLE_MACOS_TESTS = (
    "tooling.tests.test_macos_guest_artifact_manifest_composer",
    "tooling.tests.test_macos_installer_component_cpio",
    "tooling.tests.test_macos_release_package_assembly",
    "tooling.tests.test_macos_development_release_input_preparer",
    "tooling.tests.test_macos_development_guest_boot_input_assembly",
    "tooling.tests.test_macos_clean_host_release_evidence_runner",
    "tooling.tests.test_macos_development_installation_evidence_runner",
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
    def test_portable_check_excludes_apple_sdk_compilation(self) -> None:
        plan = make_plan("check")

        self.assertNotIn(MACOS_PROVIDER_COMMAND, plan)

    def test_portable_check_keeps_macos_contract_and_package_policy_tests(self) -> None:
        plan = make_plan("check")

        for test_module in (*PORTABLE_MACOS_TESTS, MACOS_PACKAGE_TEST):
            with self.subTest(test_module=test_module):
                self.assertIn(test_module, plan)

    def test_exactly_five_package_tests_are_explicitly_darwin_gated(self) -> None:
        tree = ast.parse(MACOS_PACKAGE_TEST_SOURCE.read_text(encoding="utf-8"))
        declared_methods: tuple[str, ...] | None = None
        gated_methods: set[str] = set()
        darwin_gate: ast.Call | None = None

        for node in tree.body:
            if isinstance(node, ast.Assign):
                target_names = {
                    target.id
                    for target in node.targets
                    if isinstance(target, ast.Name)
                }
                if "MACOS_NATIVE_PACKAGE_TOOL_TESTS" in target_names:
                    declared_methods = ast.literal_eval(node.value)
                if "requires_macos_native_package_tools" in target_names:
                    self.assertIsInstance(node.value, ast.Call)
                    darwin_gate = node.value
            if (
                isinstance(node, ast.ClassDef)
                and node.name == "MacOSHostPackageComposerTests"
            ):
                for member in node.body:
                    if not isinstance(member, ast.FunctionDef):
                        continue
                    if any(
                        isinstance(decorator, ast.Name)
                        and decorator.id
                        == "requires_macos_native_package_tools"
                        for decorator in member.decorator_list
                    ):
                        gated_methods.add(member.name)

        self.assertIsNotNone(declared_methods)
        self.assertEqual(5, len(declared_methods))
        self.assertEqual(set(declared_methods), gated_methods)
        self.assertIsNotNone(darwin_gate)
        self.assertEqual(
            "unittest.skipUnless",
            ast.unparse(darwin_gate.func),
        )
        condition = darwin_gate.args[0]
        self.assertIsInstance(condition, ast.Compare)
        self.assertEqual("sys.platform", ast.unparse(condition.left))
        self.assertEqual(1, len(condition.ops))
        self.assertIsInstance(condition.ops[0], ast.Eq)
        self.assertEqual(
            "darwin",
            ast.literal_eval(condition.comparators[0]),
        )
        self.assertEqual(
            "requires the macOS pkgbuild and pkgutil tools",
            ast.literal_eval(darwin_gate.args[1]),
        )

    def test_macos_native_check_owns_provider_and_full_package_suite(self) -> None:
        plan = make_plan("macos-native-check")

        self.assertIn(MACOS_PROVIDER_COMMAND, plan)
        self.assertIn(MACOS_PACKAGE_TEST, plan)

    def test_macos_ci_invokes_the_native_aggregate(self) -> None:
        workflow = (
            RUNTIME_PLATFORM_ROOT.parent
            / ".github"
            / "workflows"
            / "runtime-platform-ci.yml"
        ).read_text(encoding="utf-8")

        self.assertIn(
            "make -C runtime-platform macos-native-check",
            workflow,
        )
