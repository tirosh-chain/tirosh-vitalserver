"""Contract kernel behavior and compatibility tests."""

from __future__ import annotations

import copy
import shutil
import tempfile
import unittest
from pathlib import Path

from tooling import contracts


class ContractKernelTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.repository = contracts.ContractRepository(cls.root)
        cls.repository.load()

    def test_current_contract_source_has_no_findings(self) -> None:
        self.assertEqual([], contracts.verify_all(self.repository))

    def test_archive_contract_catalog_declares_command_manifest_and_export_receipt(self) -> None:
        catalog = contracts.load_json(self.repository.catalog_path)
        archive_contract = next(
            entry for entry in catalog["contracts"] if entry["id"] == "C6"
        )

        self.assertEqual(
            [
                "json-schema/v1/artifact-export-command.schema.json",
                "json-schema/v1/archive-export-provider.schema.json",
                "json-schema/v1/artifact-manifest.schema.json",
                "json-schema/v1/export-receipt.schema.json",
                "json-schema/v1/archive-artifact-detail.schema.json",
                "json-schema/v1/recorder-artifact-page.schema.json",
            ],
            archive_contract["schemas"],
        )

    def test_host_guest_control_contract_catalog_has_explicit_owners(self) -> None:
        catalog = contracts.load_json(self.repository.catalog_path)
        by_id = {entry["id"]: entry for entry in catalog["contracts"]}

        self.assertEqual("Host Agent", by_id["C7"]["owner"])
        self.assertEqual("Host Agent", by_id["C8"]["owner"])
        self.assertEqual("Host Agent", by_id["C9"]["owner"])
        self.assertEqual("Platform provider", by_id["C10"]["owner"])
        self.assertEqual("Host Agent", by_id["C11"]["owner"])
        self.assertEqual("Host Agent or Guest Runtime", by_id["C12"]["owner"])
        self.assertEqual("Recorder Gateway", by_id["C13"]["owner"])
        self.assertEqual("Guest Runtime Lab", by_id["C14"]["owner"])
        self.assertEqual("Guest Runtime Lab", by_id["C15"]["owner"])
        self.assertEqual("Guest Runtime External Upstream", by_id["C16"]["owner"])
        self.assertEqual("Guest Runtime Relay", by_id["C17"]["owner"])
        self.assertEqual("Host Time Authority or Guest Time Authority", by_id["C18"]["owner"])
        self.assertEqual("Vital Recorder source and Guest Runtime Observation Catalog projection", by_id["C19"]["owner"])
        self.assertEqual("Host Telemetry Pipeline or Guest Telemetry Pipeline", by_id["C20"]["owner"])
        self.assertEqual("Host Agent", by_id["C21"]["owner"])
        self.assertEqual("Platform provider", by_id["C22"]["owner"])
        self.assertEqual("Release process", by_id["C23"]["owner"])
        self.assertEqual("Release process", by_id["C24"]["owner"])
        self.assertEqual("Guest image compiler", by_id["C35"]["owner"])
        self.assertEqual("Host edge proxy deployment", by_id["C36"]["owner"])
        self.assertEqual("Guest product process supervisor", by_id["C37"]["owner"])
        self.assertEqual("Guest product service manager deployment", by_id["C38"]["owner"])
        self.assertEqual("Guest Product release author", by_id["C39"]["owner"])
        self.assertEqual("Guest Product bootstrap release composer", by_id["C40"]["owner"])
        self.assertEqual("Release input assembler", by_id["C41"]["owner"])
        self.assertEqual("Guest Linux boot artifact extractor", by_id["C42"]["owner"])
        self.assertEqual("Guest root storage partition assembler", by_id["C43"]["owner"])
        self.assertEqual("Guest Product release author", by_id["C44"]["owner"])
        self.assertEqual("Recorder Gateway", by_id["C45"]["owner"])
        self.assertEqual("Guest Product external delivery deployment administrator", by_id["C46"]["owner"])
        self.assertEqual("Release process", by_id["C47"]["owner"])
        self.assertEqual("Release process", by_id["C48"]["owner"])
        self.assertEqual("Host Installation Manager", by_id["C49"]["owner"])
        self.assertEqual("Host Installation Manager", by_id["C50"]["owner"])
        self.assertEqual("Host Installation Manager", by_id["C54"]["owner"])
        self.assertEqual("Guest secret-material owner", by_id["C51"]["owner"])
        self.assertEqual("Guest secret-material owner", by_id["C60"]["owner"])
        self.assertEqual("Guest Product release delivery", by_id["C61"]["owner"])
        self.assertEqual("Host deployment configuration", by_id["C62"]["owner"])
        self.assertEqual("Selected native Platform Provider", by_id["C63"]["owner"])
        self.assertEqual("Guest Bundled Upstream Image-set Manager", by_id["C64"]["owner"])
        self.assertEqual("Guest Bundled Upstream release delivery", by_id["C66"]["owner"])
        self.assertEqual("Guest image compiler", by_id["C65"]["owner"])
        self.assertEqual("Host Platform release delivery", by_id["C67"]["owner"])
        self.assertEqual("Host Installation Manager", by_id["C68"]["owner"])
        self.assertEqual("Host update bundle store and Host Agent", by_id["C69"]["owner"])
        self.assertEqual("Release process", by_id["C70"]["owner"])
        self.assertEqual("Runtime Console packager", by_id["C71"]["owner"])
        self.assertEqual("Release process", by_id["C72"]["owner"])
        self.assertEqual("Guest Linux source disk materializer", by_id["C73"]["owner"])
        self.assertEqual("Release process", by_id["C74"]["owner"])
        self.assertEqual("Guest Runtime Lab replay", by_id["C75"]["owner"])
        self.assertEqual("Guest operational-state backup workflow", by_id["C76"]["owner"])
        self.assertEqual(
            "Guest operational-state and bootstrap evidence owners",
            by_id["C77"]["owner"],
        )
        self.assertEqual(
            "Guest installed-runtime release evidence runner",
            by_id["C78"]["owner"],
        )
        self.assertEqual("Release data review", by_id["C79"]["owner"])
        self.assertEqual("Host Agent", by_id["C80"]["owner"])
        self.assertEqual("Host Agent", by_id["C81"]["owner"])

    def test_checked_in_guest_bootstrap_configurations_are_explicit_valid_architecture_inputs(self) -> None:
        product_root = self.root / "product" / "guest-product"
        expected_artifact_suffixes = {
            "arm64": "linux-arm64",
            "amd64": "linux-amd64",
        }

        for architecture, suffix in expected_artifact_suffixes.items():
            filename = (
                "guest-product-bootstrap-configuration.v1.json"
                if architecture == "arm64"
                else "guest-product-bootstrap-configuration-amd64.v1.json"
            )
            configuration = contracts.load_json(product_root / filename)

            self.assertEqual(
                [],
                self.repository.validate_instance(
                    "guest-product-bootstrap-configuration.schema.json", configuration
                ),
                filename,
            )
            self.assertEqual(architecture, configuration["guestArchitecture"])
            self.assertTrue(
                configuration["guestRuntime"]["artifactId"].endswith(suffix)
            )
            self.assertTrue(
                configuration["guestTelemetryCollector"]["artifactId"].endswith(suffix)
            )
            self.assertTrue(
                configuration["guestNodeServicesBundle"]["artifactId"].endswith(suffix)
            )
            self.assertTrue(
                configuration["guestProductProcessSupervisor"]["artifactId"].endswith(suffix)
            )
            self.assertTrue(
                configuration["guestProductReleaseManager"]["executable"]["artifactId"].endswith(suffix)
            )

    def test_host_installation_footprint_accepts_explicit_windows_paths(self) -> None:
        root = r"C:\ProgramData\VitalServerRuntimePlatform"
        footprint = {
            "schemaVersion": "v1",
            "installationId": "vitalserver-runtime-platform",
            "expectedReleaseId": "runtime-platform-0.2.0-dev-build-001",
            "platform": "windows",
            "observedAt": "2026-07-19T00:00:00Z",
            "packageReceipt": {
                "state": "absent",
                "identifier": "com.tirosh.vitalserver.runtime-platform",
            },
            "releaseCatalog": {"state": "absent", "releaseCatalogPath": root + r"\releases"},
            "immutableRelease": {
                "state": "absent",
                "releaseRootPath": root + r"\releases\runtime-platform-0.2.0-dev-build-001",
            },
            "activation": {"state": "absent", "currentReleaseLinkPath": root + r"\current"},
            "requiredServices": [
                {"role": "host-agent", "name": "VitalServerHostAgent", "state": "absent", "definitionState": "absent"},
                {"role": "host-edge-proxy", "name": "VitalServerHostEdgeProxy", "state": "absent", "definitionState": "absent"},
                {"role": "host-update-handoff-supervisor", "name": "VitalServerHostUpdateHandoffSupervisor", "state": "absent", "definitionState": "absent"},
            ],
            "mutableStores": [{"id": "native-machine-runtime", "state": "absent"}],
            "installationTransaction": {
                "state": "absent",
                "journalPath": root + r"\data\installation-manager\current-transaction.json",
                "receiptPath": root + r"\data\installation-manager\latest-installation-receipt.json",
            },
        }

        self.assertEqual(
            [],
            self.repository.validate_instance("host-installation-footprint.schema.json", footprint),
        )

    def test_host_product_installation_manifest_binds_native_service_and_activation_contracts(self) -> None:
        manifest = contracts.load_json(
            self.root / "contracts" / "examples" / "v1" / "valid" / "host-product-installation-manifest.json"
        )
        linux = copy.deepcopy(manifest)
        linux["platform"] = "linux"
        for service in linux["requiredServices"]:
            service["manager"] = "systemd"
        self.assertEqual(
            [],
            self.repository.validate_instance("host-product-installation-manifest.schema.json", linux),
        )

        linux["activation"]["referenceKind"] = "directory-junction"
        self.assertNotEqual(
            [],
            self.repository.validate_instance("host-product-installation-manifest.schema.json", linux),
        )

        windows = copy.deepcopy(manifest)
        windows["platform"] = "windows"
        windows["activation"]["referenceKind"] = "directory-junction"
        for service in windows["requiredServices"]:
            service["manager"] = "windows-scm"
        self.assertEqual(
            [],
            self.repository.validate_instance("host-product-installation-manifest.schema.json", windows),
        )
        windows["requiredServices"][0]["manager"] = "launchd"
        self.assertNotEqual(
            [],
            self.repository.validate_instance("host-product-installation-manifest.schema.json", windows),
        )

    def test_extend_baseline_refuses_a_breaking_existing_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            shutil.copytree(self.root / "contracts", root / "contracts")
            read_result_path = root / "contracts" / "json-schema" / "v1" / "read-result.schema.json"
            candidate = contracts.load_json(read_result_path)
            del candidate["properties"]["observedAt"]
            contracts.write_json(read_result_path, candidate)
            repository = contracts.ContractRepository(root)
            repository.load()

            with self.assertRaises(contracts.ContractToolError):
                contracts.extend_baseline(repository)

    def test_extend_baseline_records_an_additive_schema_only_after_checking_existing_v1(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            shutil.copytree(self.root / "contracts", root / "contracts")
            new_schema_path = root / "contracts" / "json-schema" / "v1" / "test-additive.schema.json"
            contracts.write_json(
                new_schema_path,
                {
                    "$schema": "https://json-schema.org/draft/2020-12/schema",
                    "$id": "urn:tirosh:vitalserver:runtime-platform:v1:test-additive",
                    "type": "object",
                    "additionalProperties": False,
                },
            )
            repository = contracts.ContractRepository(root)
            repository.load()

            contracts.extend_baseline(repository)
            baseline = contracts.load_json(repository.baseline_path)

            self.assertIn("json-schema/v1/test-additive.schema.json", baseline["schemas"])

    def test_replace_baseline_for_unreleased_contracts_replaces_explicitly_selected_history(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            shutil.copytree(self.root / "contracts", root / "contracts")
            removed_schema_path = root / "contracts" / "json-schema" / "v1" / "read-result.schema.json"
            removed_schema_path.unlink()
            repository = contracts.ContractRepository(root)
            repository.load()

            baseline = contracts.replace_baseline_for_unreleased_contracts(repository)

            self.assertNotIn("json-schema/v1/read-result.schema.json", baseline["schemas"])

    def test_replace_baseline_for_unreleased_contracts_requires_an_existing_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            shutil.copytree(self.root / "contracts", root / "contracts")
            baseline_path = root / "contracts" / "compatibility" / "v1" / "baseline.json"
            baseline_path.unlink()
            repository = contracts.ContractRepository(root)
            repository.load()

            with self.assertRaises(contracts.ContractToolError):
                contracts.replace_baseline_for_unreleased_contracts(repository)

    def test_operation_transition_policy_allows_only_declared_edges(self) -> None:
        policy = contracts.load_operation_policy(self.repository)

        self.assertTrue(contracts.transition_allowed(policy, "requested", "accepted"))
        self.assertFalse(contracts.transition_allowed(policy, "requested", "failed"))
        self.assertFalse(contracts.transition_allowed(policy, "succeeded", "running"))

    def test_v1_allows_an_optional_schema_property(self) -> None:
        _, baseline = self.repository.schema("operation.schema.json")
        candidate = copy.deepcopy(baseline)
        candidate["properties"]["operatorNote"] = {"type": "string"}

        self.assertEqual([], contracts.compare_schema(baseline, candidate))

    def test_v1_rejects_a_removed_schema_property(self) -> None:
        _, baseline = self.repository.schema("operation.schema.json")
        candidate = copy.deepcopy(baseline)
        del candidate["properties"]["state"]

        findings = contracts.compare_schema(baseline, candidate)

        self.assertTrue(any("removed or renamed" in finding for finding in findings))

    def test_v1_rejects_an_enum_change(self) -> None:
        _, baseline = self.repository.schema("operation.schema.json")
        candidate = copy.deepcopy(baseline)
        candidate["properties"]["state"]["enum"].append("paused")

        findings = contracts.compare_schema(baseline, candidate)

        self.assertTrue(any("enum changed" in finding for finding in findings))

    def test_v1_rejects_an_existing_openapi_response_change(self) -> None:
        baseline = contracts.load_json(self.repository.openapi_path)
        candidate = copy.deepcopy(baseline)
        candidate["paths"]["/v1/runtime/topology"]["get"]["responses"]["200"]["content"] = {}

        findings = contracts.compare_openapi(baseline, candidate)

        self.assertTrue(any("response content changed" in finding for finding in findings))

    def test_resolved_openapi_bundle_has_no_external_reference(self) -> None:
        bundle = contracts.bundle_openapi(self.repository)

        self.assertTrue(
            all(reference.startswith("#") for reference in contracts.iter_references(bundle))
        )


if __name__ == "__main__":
    unittest.main()
