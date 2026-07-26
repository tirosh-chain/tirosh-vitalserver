"""Focused tests for the independent-root boundary verifier."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tooling import verify_boundaries


def create_required_directories(root: Path) -> None:
    for relative_path in verify_boundaries.REQUIRED_DIRECTORIES:
        (root / relative_path).mkdir(parents=True, exist_ok=True)


def create_contextual_product_process_layer_directories(root: Path) -> None:
    for relative_path in verify_boundaries.CONTEXTUAL_PRODUCT_PROCESS_LAYER_DIRECTORIES:
        (root / relative_path).mkdir(parents=True, exist_ok=True)


def create_contextual_recorder_gateway_layer_directories(root: Path) -> None:
    for relative_path in verify_boundaries.CONTEXTUAL_RECORDER_GATEWAY_LAYER_DIRECTORIES:
        (root / relative_path).mkdir(parents=True, exist_ok=True)


class VerifyBoundariesTests(unittest.TestCase):
    def test_current_root_satisfies_independent_boundary(self) -> None:
        root = Path(__file__).resolve().parents[2]

        self.assertEqual([], verify_boundaries.validate(root))

    def test_reports_every_missing_required_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)

            violations = verify_boundaries.validate(root)

        self.assertEqual(
            len(verify_boundaries.REQUIRED_DIRECTORIES),
            len(violations),
        )
        self.assertTrue(
            all(
                violation.code == "required-directory-missing"
                for violation in violations
            )
        )

    def test_rejects_a_legacy_source_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            source_file = root / "services/host-agent/main.go"
            source_file.write_text(
                'package main\nimport "github.com/tirosh/vitalserver-platform-agent"\n',
                encoding="utf-8",
            )

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("legacy-coupling", violations[0].code)
        self.assertIn("github.com/tirosh/vitalserver-", violations[0].message)

    def test_rejects_a_relative_parent_workspace_import(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            source_file = root / "services/runtime-pwa/source.ts"
            source_file.write_text(
                'import "../../../apps/vitalserver-runtime-pwa/source";\n',
                encoding="utf-8",
            )

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("legacy-coupling", violations[0].code)
        self.assertIn("relative path", violations[0].message)

    def test_rejects_a_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            symlink = root / "services/host-agent/linked-contracts"
            symlink.symlink_to(root / "contracts", target_is_directory=True)

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("symlink-not-allowed", violations[0].code)

    def test_rejects_a_persistent_path_named_for_temporary_work_order(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            temporary_path = root / "services/host-agent/phase2-recovery"
            temporary_path.mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("temporary-work-order-path-not-allowed", violations[0].code)
        self.assertIn("owner, domain, boundary, or role", violations[0].message)

    def test_rejects_a_generic_product_process_layer_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_product_process_layer_directories(root)
            generic_layer_directory = root / "services/guest-runtime/internal/application"
            generic_layer_directory.mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("generic-product-process-layer-not-allowed", violations[0].code)
        self.assertIn("bounded-context ownership", violations[0].message)

    def test_rejects_a_generic_host_edge_proxy_role_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_product_process_layer_directories(root)
            generic_role_directory = root / "services/host-edge-proxy/internal/edgehttpserver"
            generic_role_directory.mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("generic-product-process-layer-not-allowed", violations[0].code)
        self.assertIn("Host Edge Proxy", violations[0].message)

    def test_rejects_a_generic_host_updater_layer_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_product_process_layer_directories(root)
            generic_layer_directory = root / "services/host-updater/internal/domain"
            generic_layer_directory.mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("generic-product-process-layer-not-allowed", violations[0].code)
        self.assertIn("Host Updater", violations[0].message)

    def test_rejects_a_guest_product_deployment_configuration_reader_without_file_adapter_context(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_product_process_layer_directories(root)
            generic_configuration_reader_directory = (
                root
                / "services/guest-product-process-supervisor/internal/adapters/configurationfile"
            )
            generic_configuration_reader_directory.mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("generic-product-process-layer-not-allowed", violations[0].code)
        self.assertIn("external mechanism", violations[0].message)

    def test_requires_contextual_layer_names_after_a_product_process_internal_tree_exists(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            (root / "services/host-agent/internal").mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(
            len(verify_boundaries.CONTEXTUAL_PRODUCT_PROCESS_LAYER_DIRECTORIES),
            len(violations),
        )
        self.assertTrue(
            all(
                violation.code == "contextual-product-process-layer-missing"
                for violation in violations
            )
        )

    def test_rejects_ambiguous_product_process_application_method_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_product_process_layer_directories(root)
            source_file = (
                root
                / "services/guest-runtime/internal/guestruntimeapplication"
                / "guest_runtime_topology_application_service.go"
            )
            source_file.write_text(
                "package guestruntimeapplication\n\n"
                "func (service *GuestRuntimeTopologyApplicationService) GetTopology() {}\n",
                encoding="utf-8",
            )

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("ambiguous-product-process-application-method", violations[0].code)
        self.assertIn("aggregate or effect", violations[0].message)

    def test_rejects_a_generic_guest_runtime_operational_port_file(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_product_process_layer_directories(root)
            generic_port_file = root / verify_boundaries.FORBIDDEN_GENERIC_GUEST_RUNTIME_APPLICATION_FILES[0]
            generic_port_file.write_text("package guestruntimeapplication\n", encoding="utf-8")

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("generic-guest-runtime-operational-port-file-not-allowed", violations[0].code)
        self.assertIn("separate bounded-context names", violations[0].message)

    def test_rejects_an_ambiguous_host_updater_domain_declaration(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_product_process_layer_directories(root)
            source_file = (
                root
                / "services/host-updater/internal/hostupdaterdomain"
                / "product_update_specification.go"
            )
            source_file.write_text(
                "package hostupdaterdomain\n\n"
                "type Artifact struct{}\n",
                encoding="utf-8",
            )

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("ambiguous-host-updater-domain-declaration", violations[0].code)
        self.assertIn("staged product-update context", violations[0].message)

    def test_rejects_generic_recorder_gateway_upstream_adapter_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_recorder_gateway_layer_directories(root)
            adapter_root = root / verify_boundaries.RECORDER_GATEWAY_ADAPTER_DIRECTORY
            (adapter_root / "upstream").mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("generic-recorder-gateway-delivery-adapter-not-allowed", violations[0].code)
        self.assertIn("VitalServer packet-delivery contract", violations[0].message)

    def test_rejects_a_generic_recorder_gateway_layer_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_recorder_gateway_layer_directories(root)
            generic_layer_directory = root / "services/recorder-gateway/src/application"
            generic_layer_directory.mkdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("generic-recorder-gateway-layer-not-allowed", violations[0].code)
        self.assertIn("managed resource", violations[0].message)

    def test_rejects_an_ambiguous_recorder_gateway_application_method_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_recorder_gateway_layer_directories(root)
            source_file = (
                root
                / "services/recorder-gateway/src/recordergatewayapplication"
                / "recorder-gateway-ingress-and-cold-path-application-service.ts"
            )
            source_file.write_text(
                "export class RecorderGatewayIngressAndColdPathApplicationService {\n"
                "  public async getReceipt(): Promise<void> {}\n"
                "}\n",
                encoding="utf-8",
            )

            violations = verify_boundaries.validate(root)

        self.assertEqual(1, len(violations))
        self.assertEqual("ambiguous-recorder-gateway-application-method", violations[0].code)
        self.assertIn("managed packet, receipt, durable ingress state", violations[0].message)

    def test_requires_named_recorder_gateway_vitalserver_delivery_adapter_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            create_contextual_recorder_gateway_layer_directories(root)
            (root / verify_boundaries.REQUIRED_RECORDER_GATEWAY_VITALSERVER_DELIVERY_ADAPTER_DIRECTORY).rmdir()

            violations = verify_boundaries.validate(root)

        self.assertEqual(2, len(violations))
        self.assertEqual(
            [
                "contextual-recorder-gateway-layer-missing",
                "recorder-gateway-vitalserver-delivery-adapter-missing",
            ],
            [violation.code for violation in violations],
        )
        self.assertIn("VitalServer packet-delivery boundary", violations[1].message)

    def test_allows_a_generated_virtual_environment_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            virtual_environment = root / ".venv"
            virtual_environment.mkdir()
            (virtual_environment / "python").symlink_to("/usr/bin/python3")

            violations = verify_boundaries.validate(root)

        self.assertEqual([], violations)

    def test_ignores_generated_swift_build_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            generated_source = root / "providers/macos-virtualization/.build/generated.swift"
            generated_source.parent.mkdir(parents=True)
            generated_source.write_text(
                'import "../../../apps/vitalserver-runtime/source"\n',
                encoding="utf-8",
            )

            violations = verify_boundaries.validate(root)

        self.assertEqual([], violations)

    def test_ignores_explicit_release_evidence_staging_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            create_required_directories(root)
            staged_release_symlink = root / ".tmp/c42-release-source/bin/npm"
            staged_release_symlink.parent.mkdir(parents=True)
            staged_release_symlink.symlink_to("../node")

            violations = verify_boundaries.validate(root)

        self.assertEqual([], violations)


if __name__ == "__main__":
    unittest.main()
