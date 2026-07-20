from __future__ import annotations

from dataclasses import replace
import json
import os
from pathlib import Path
import tempfile
import unittest

from tooling import windows_host_msi_composer
from tooling import windows_host_release_input_preparer as preparer


class WindowsHostReleaseInputPreparerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.release_root = self.root / "release-workspace"
        self.release_root.mkdir()
        self.documents = self.root / "documents"
        self.documents.mkdir()
        self.binaries = self.root / "binaries"
        self.binaries.mkdir()
        self.product_root = preparer.PRODUCT_ROOT
        self.current = self.product_root + r"\current"
        for name in (
            "host-agent.exe",
            "host-edge-proxy.exe",
            "host-installation-manager.exe",
            "host-service-runner.exe",
            "host-update-handoff-supervisor.exe",
            "platformctl.exe",
            "windows-hyperv-scm-bridge.exe",
        ):
            (self.binaries / name).write_bytes(name.encode("utf-8"))
        self.host_agent = self._write("host-agent.json", {
            "schemaVersion": "v1",
            "control": {
                "localAdministration": {
                    "transport": "windows-named-pipe",
                    "endpointAddress": r"\\.\pipe\VitalServerRuntimePlatform.HostAgent",
                    "descriptorPath": self.product_root + r"\control\host-agent.local.json",
                    "securityDescriptor": "D:(A;;GA;;;SY)(A;;GA;;;BA)",
                },
                "loopbackHTTP": {"mode": "disabled"},
                "stateDatabasePath": self.product_root + r"\data\host-agent\host-agent.sqlite",
                "guestTimeoutMilliseconds": 5000,
            },
            "installation": {
                "installationId": "vitalserver-runtime-platform-windows-reference",
                "productVersion": "0.2.0",
                "runtimeVersion": "0.2.0",
                "dataDirectory": self.product_root + r"\data",
            },
            "guestRuntimeControlEndpoint": {"id": "guest-runtime", "scheme": "http", "host": "192.0.2.10", "port": 18443},
            "provider": {
                "kind": "windows-hyperv-scm",
                "id": "vitalserver-windows-hyperv-provider",
                "nativeProviderBridgeExecutablePath": self.current + r"\bin\windows-hyperv-scm-bridge.exe",
                "nativeVirtualMachineName": "vitalserver-guest",
                "hostServiceName": "VitalServerHostAgent",
                "nativeGuestMachineOwnership": "externally-provisioned",
            },
            "time": {"hostNodeId": "vitalserver-windows-host", "timeAuthorityId": "vitalserver-windows-time", "kind": "time-authority-outcome-profile", "providerMode": "outcome-unknown"},
            "telemetry": {"kind": "telemetry-export-outcome-profile", "pipelineMode": "outcome-unknown", "exportMode": "outcome-unknown"},
            "updateBootstrap": {
                "mode": "staged",
                "bundleStoreDirectory": self.product_root + r"\data\update-bundles",
                "stagingDirectory": self.product_root + r"\data\update-staging",
                "trustStorePath": self.current + r"\config\update-trust-store.json",
            },
        })
        self.host_edge = self._write("host-edge.json", {
            "schemaVersion": "v1",
            "proxyId": "vitalserver-windows-public-edge",
            "listener": {"protocol": "http", "bindHost": "0.0.0.0", "port": 8088},
            "readinessPath": "/ready",
            "clientIdentityHeaderPolicy": "replace-with-remote-address",
            "routes": [{
                "id": "recorder-gateway",
                "requestPathPrefix": "/socket.io/",
                "target": {"scheme": "http", "host": "192.0.2.10", "port": 18090},
                "forwardingProtocol": "http-and-websocket",
                "requestHostHeaderPolicy": "preserve-client-host",
                "maximumRequestBodyBytes": 4194304,
                "upstreamResponseHeaderTimeoutMilliseconds": 30000,
            }],
        })
        self.handoff = self._write("handoff.json", {
            "schemaVersion": "v1",
            "id": "vitalserver-windows-handoff-supervisor",
            "stagingDirectory": self.product_root + r"\data\update-staging",
            "handoffQueueDirectory": self.product_root + r"\data\update-staging\handoff-queue",
            "executionEvidenceDirectory": self.product_root + r"\data\update-execution",
            "layerEffectReceiptDirectory": self.product_root + r"\data\update-layer-effects",
            "hostLocalAdministrationDescriptorPath": self.product_root + r"\control\host-agent.local.json",
            "layerEffectTimeoutMilliseconds": 300000,
            "completionTimeoutMilliseconds": 30000,
            "servicePollIntervalMilliseconds": 1000,
        })
        self.operator = self._write("operator.json", {
            "schemaVersion": "v1",
            "bootstrapConfigurationPath": self.product_root + r"\control\runtime-console-bootstrap.json",
            "localAdministrationDescriptorPath": self.product_root + r"\control\host-agent.local.json",
        })
        self.trust = self._write("trust.json", {
            "schemaVersion": "v1",
            "keys": [{"id": "release-key-2026", "algorithm": "ed25519", "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}],
        })

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(self, name: str, value: object) -> Path:
        path = self.documents / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def preparation(self) -> preparer.WindowsHostReleaseInputPreparation:
        return preparer.WindowsHostReleaseInputPreparation(
            release_root=self.release_root,
            release_slot_id="runtime-platform-0.2.0-build-001",
            release_delivery_plans_document=(Path(__file__).resolve().parents[2] / "product" / "delivery" / "release-delivery-plans.v1.json"),
            release_delivery_plan_id="windows-runtime-platform-release",
            package_product_code="{12345678-1234-1234-1234-1234567890AB}",
            manufacturer="Tirosh",
            upgrade_code="{87654321-4321-4321-4321-BA0987654321}",
            host_agent_binary=self.binaries / "host-agent.exe",
            host_edge_proxy_binary=self.binaries / "host-edge-proxy.exe",
            host_installation_manager_binary=self.binaries / "host-installation-manager.exe",
            host_service_runner_binary=self.binaries / "host-service-runner.exe",
            host_update_handoff_supervisor_binary=self.binaries / "host-update-handoff-supervisor.exe",
            platformctl_binary=self.binaries / "platformctl.exe",
            windows_hyperv_scm_bridge_binary=self.binaries / "windows-hyperv-scm-bridge.exe",
            host_agent_deployment_configuration=self.host_agent,
            host_edge_proxy_deployment_configuration=self.host_edge,
            host_update_handoff_supervisor_configuration=self.handoff,
            operator_interface_bootstrap_configuration=self.operator,
            host_update_trust_store=self.trust,
        )

    def test_prepares_one_c48_source_and_composes_wix_from_the_same_bytes(self) -> None:
        result = preparer.prepare_windows_host_release_input(self.preparation())
        input_root = Path(result["releaseInputDirectory"])
        manifest = json.loads(Path(result["installationManifestPath"]).read_text(encoding="utf-8"))
        self.assertEqual("windows", manifest["platform"])
        self.assertEqual(11, len(manifest["immutablePayload"]["entries"]))
        self.assertTrue((input_root / "release" / "bin" / "platformctl.exe").is_file())
        services = manifest["requiredServices"]
        self.assertEqual(self.current + r"\bin\host-service-runner.exe", services[0]["windowsScmRegistration"]["executablePath"])
        handoff = json.loads((input_root / "services" / "host-update-handoff-supervisor.json").read_text(encoding="utf-8"))
        self.assertEqual(["--configuration", self.current + r"\config\host-update-handoff-supervisor-configuration.json", "--mode", "service"], handoff["command"]["arguments"])
        composition_document = json.loads(Path(result["windowsHostMSICompositionPath"]).read_text(encoding="utf-8"))
        composition = windows_host_msi_composer._parse_arguments(["--composition", str(result["windowsHostMSICompositionPath"])])
        wix = windows_host_msi_composer.compose_windows_host_msi(composition)
        self.assertEqual("wix-source", wix["artifactKind"])
        self.assertEqual(str(input_root / "VitalServerRuntimePlatform.wxs"), wix["artifactPath"])
        self.assertEqual(str(input_root / "release" / "installation-manifest.json"), composition_document["manifestPath"])

    def test_rejects_deployment_that_does_not_name_the_packaged_provider_bridge(self) -> None:
        document = json.loads(self.host_agent.read_text(encoding="utf-8"))
        document["provider"]["nativeProviderBridgeExecutablePath"] = self.current + r"\bin\another-bridge.exe"
        self.host_agent.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaisesRegex(preparer.WindowsHostReleaseInputPreparationError, "packaged Windows provider bridge path"):
            preparer.prepare_windows_host_release_input(self.preparation())
        self.assertFalse((self.release_root / preparer.RELEASE_INPUT_DIRECTORY_NAME).exists())

    def test_does_not_replace_an_existing_selected_release_input(self) -> None:
        preparer.prepare_windows_host_release_input(self.preparation())
        with self.assertRaisesRegex(preparer.WindowsHostReleaseInputPreparationError, "already exists"):
            preparer.prepare_windows_host_release_input(self.preparation())

    def test_checked_in_windows_reference_profile_forms_a_valid_release_input(self) -> None:
        profile = Path(__file__).resolve().parents[2] / "product" / "deployment-profiles" / "windows-hyperv-external-guest-external-vitalserver-reference"
        preparation = replace(
            self.preparation(),
            host_agent_deployment_configuration=profile / "host-agent-deployment-configuration.v1.json",
            host_edge_proxy_deployment_configuration=profile / "host-edge-proxy-deployment-configuration.v1.json",
            host_update_handoff_supervisor_configuration=profile / "host-update-handoff-supervisor-configuration.v1.json",
            operator_interface_bootstrap_configuration=profile / "operator-interface-bootstrap-configuration.v1.json",
            host_update_trust_store=profile / "update-trust-store.v1.json",
        )
        result = preparer.prepare_windows_host_release_input(preparation)
        self.assertTrue(Path(result["installationManifestPath"]).is_file())

    def test_compiles_an_msi_from_actual_windows_host_binaries_when_a_windows_wix_runner_is_declared(self) -> None:
        artifact_root = os.environ.get("RUNTIME_PLATFORM_WINDOWS_HOST_RELEASE_ARTIFACT_DIRECTORY")
        wix_executable = os.environ.get("RUNTIME_PLATFORM_WINDOWS_WIX")
        if artifact_root is None or wix_executable is None:
            self.skipTest("set actual Windows Host artifact directory and WiX executable only in the Windows package runner")
        artifacts = Path(artifact_root)
        required_artifacts = (
            "host-agent.exe",
            "host-edge-proxy.exe",
            "host-installation-manager.exe",
            "host-service-runner.exe",
            "host-update-handoff-supervisor.exe",
            "platformctl.exe",
            "windows-hyperv-scm-bridge.exe",
        )
        for name in required_artifacts:
            self.assertTrue((artifacts / name).is_file(), name)
            self.assertGreater((artifacts / name).stat().st_size, 0, name)
        profile = Path(__file__).resolve().parents[2] / "product" / "deployment-profiles" / "windows-hyperv-external-guest-external-vitalserver-reference"
        with tempfile.TemporaryDirectory() as temporary:
            release_root = Path(temporary) / "release-workspace"
            release_root.mkdir()
            preparation = replace(
                self.preparation(),
                release_root=release_root,
                release_slot_id="runtime-platform-0.2.0-windows-ci",
                package_product_code="{A13CD872-E983-48BE-B20A-202607200002}",
                host_agent_binary=artifacts / "host-agent.exe",
                host_edge_proxy_binary=artifacts / "host-edge-proxy.exe",
                host_installation_manager_binary=artifacts / "host-installation-manager.exe",
                host_service_runner_binary=artifacts / "host-service-runner.exe",
                host_update_handoff_supervisor_binary=artifacts / "host-update-handoff-supervisor.exe",
                platformctl_binary=artifacts / "platformctl.exe",
                windows_hyperv_scm_bridge_binary=artifacts / "windows-hyperv-scm-bridge.exe",
                host_agent_deployment_configuration=profile / "host-agent-deployment-configuration.v1.json",
                host_edge_proxy_deployment_configuration=profile / "host-edge-proxy-deployment-configuration.v1.json",
                host_update_handoff_supervisor_configuration=profile / "host-update-handoff-supervisor-configuration.v1.json",
                operator_interface_bootstrap_configuration=profile / "operator-interface-bootstrap-configuration.v1.json",
                host_update_trust_store=profile / "update-trust-store.v1.json",
            )
            result = preparer.prepare_windows_host_release_input(preparation)
            composition = windows_host_msi_composer._parse_arguments(["--composition", result["windowsHostMSICompositionPath"]])
            package = release_root / "VitalServerRuntimePlatform-0.2.0.msi"
            compiled = windows_host_msi_composer.compose_windows_host_msi(
                replace(composition, wix_executable_path=Path(wix_executable), output_package=package)
            )
            self.assertEqual("msi", compiled["artifactKind"])
            self.assertTrue(package.is_file())
            self.assertGreater(package.stat().st_size, 0)

if __name__ == "__main__":
    unittest.main()
