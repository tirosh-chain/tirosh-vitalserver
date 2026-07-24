from __future__ import annotations

from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest

from tooling import linux_host_package_composer
from tooling import linux_host_release_input_preparer as preparer


class LinuxHostReleaseInputPreparerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.release_root = self.root / "release-workspace"
        self.release_root.mkdir()
        self.documents = self.root / "documents"
        self.documents.mkdir()
        self.binaries = self.root / "binaries"
        self.binaries.mkdir()
        self.current = preparer.PRODUCT_ROOT + "/current"
        for name in (
            "host-agent", "host-edge-proxy", "host-installation-manager",
            "host-update-handoff-supervisor", "platformctl", "linux-kvm-libvirt-systemd-bridge",
        ):
            path = self.binaries / name
            path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            path.chmod(0o755)
        self.host_agent = self._write("host-agent.json", {
            "schemaVersion": "v1",
            "control": {
                "localAdministration": {
                    "transport": "unix-domain-socket",
                    "endpointAddress": "/run/vitalserver-runtime-platform/host-agent.sock",
                    "descriptorPath": preparer.CONTROL_ROOT + "/host-agent.local.json",
                    "authorizedUserId": 0,
                },
                "loopbackHTTP": {"mode": "disabled"},
                "stateDatabasePath": preparer.DATA_ROOT + "/host-agent/host-agent.sqlite",
                "guestTimeoutMilliseconds": 5000,
            },
            "installation": {
                "installationId": "vitalserver-runtime-platform-linux-reference",
                "productVersion": "0.2.0-dev", "runtimeVersion": "0.2.0-dev",
                "dataDirectory": preparer.DATA_ROOT,
            },
            "guestRuntimeControlEndpoint": {"id": "linux-guest", "scheme": "http", "host": "192.0.2.10", "port": 18443},
            "operationalStateBackup": {
                "scheduleId": "daily-primary",
                "intervalSeconds": 86400,
                "retryIntervalSeconds": 60,
                "destinationReference": {
                    "resourceType": "guest-backup-destination",
                    "resourceId": "guest-local-operational-state",
                },
                "retentionPolicy": "retain-all",
            },
            "provider": {
                "kind": "linux-kvm-libvirt-systemd", "id": "linux-reference-provider",
                "nativeProviderBridgeExecutablePath": self.current + "/bin/linux-kvm-libvirt-systemd-bridge",
                "nativeVirtualMachineName": "vitalserver-guest",
                "hostServiceName": "vitalserver-host-agent.service",
                "nativeGuestMachineOwnership": "externally-provisioned",
            },
            "time": {"hostNodeId": "linux-reference-host", "timeAuthorityId": "linux-reference-time", "kind": "time-authority-outcome-profile", "providerMode": "outcome-unknown"},
            "telemetry": {"kind": "telemetry-export-outcome-profile", "pipelineMode": "outcome-unknown", "exportMode": "outcome-unknown"},
            "updateBootstrap": {"mode": "staged", "bundleStoreDirectory": preparer.DATA_ROOT + "/update-bundles", "stagingDirectory": preparer.DATA_ROOT + "/update-staging", "trustStorePath": self.current + "/config/update-trust-store.json"},
        })
        self.host_edge = self._write("host-edge.json", {
            "schemaVersion": "v1", "proxyId": "linux-public-edge",
            "listener": {"protocol": "http", "bindHost": "0.0.0.0", "port": 8088},
            "readinessPath": "/ready", "clientIdentityHeaderPolicy": "replace-with-remote-address",
            "routes": [{"id": "recorder-gateway", "requestPathPrefix": "/socket.io/", "target": {"scheme": "http", "host": "192.0.2.10", "port": 18090}, "forwardingProtocol": "http-and-websocket", "requestHostHeaderPolicy": "preserve-client-host", "maximumRequestBodyBytes": 4194304, "upstreamResponseHeaderTimeoutMilliseconds": 30000}],
        })
        self.handoff = self._write("handoff.json", {
            "schemaVersion": "v1", "id": "linux-handoff-supervisor",
            "stagingDirectory": preparer.DATA_ROOT + "/update-staging",
            "handoffQueueDirectory": preparer.DATA_ROOT + "/update-staging/handoff-queue",
            "executionEvidenceDirectory": preparer.DATA_ROOT + "/update-execution",
            "layerEffectReceiptDirectory": preparer.DATA_ROOT + "/update-layer-effects",
            "hostLocalAdministrationDescriptorPath": preparer.CONTROL_ROOT + "/host-agent.local.json",
            "layerEffectTimeoutMilliseconds": 300000, "completionTimeoutMilliseconds": 30000,
            "servicePollIntervalMilliseconds": 1000,
        })
        self.operator = self._write("operator.json", {
            "schemaVersion": "v1", "bootstrapConfigurationPath": preparer.CONTROL_ROOT + "/runtime-console-bootstrap.json",
            "localAdministrationDescriptorPath": preparer.CONTROL_ROOT + "/host-agent.local.json",
        })
        self.trust = self._write("trust.json", {
            "schemaVersion": "v1", "keys": [{"id": "release-key-2026", "algorithm": "ed25519", "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}],
        })

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(self, name: str, document: object) -> Path:
        path = self.documents / name
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def preparation(self) -> preparer.LinuxHostReleaseInputPreparation:
        return preparer.LinuxHostReleaseInputPreparation(
            release_root=self.release_root, release_slot_id="runtime-platform-0.2.0-dev-linux-test",
            release_delivery_plans_document=Path(__file__).resolve().parents[2] / "product" / "delivery" / "release-delivery-plans.v1.json",
            release_delivery_plan_id="linux-runtime-platform-release", package_maintainer="Tirosh <support@tirosh.example>", package_description="VitalServer Runtime Platform",
            host_agent_binary=self.binaries / "host-agent", host_edge_proxy_binary=self.binaries / "host-edge-proxy",
            host_installation_manager_binary=self.binaries / "host-installation-manager",
            host_update_handoff_supervisor_binary=self.binaries / "host-update-handoff-supervisor",
            platformctl_binary=self.binaries / "platformctl",
            linux_kvm_libvirt_systemd_bridge_binary=self.binaries / "linux-kvm-libvirt-systemd-bridge",
            host_agent_deployment_configuration=self.host_agent, host_edge_proxy_deployment_configuration=self.host_edge,
            host_update_handoff_supervisor_configuration=self.handoff, operator_interface_bootstrap_configuration=self.operator,
            host_update_trust_store=self.trust,
        )

    def test_prepares_one_c48_source_and_composes_a_deb_from_the_same_bytes(self) -> None:
        result = preparer.prepare_linux_host_release_input(self.preparation())
        input_root = Path(result["releaseInputDirectory"])
        manifest = json.loads(Path(result["installationManifestPath"]).read_text(encoding="utf-8"))
        self.assertEqual("linux", manifest["platform"])
        self.assertEqual(10, len(manifest["immutablePayload"]["entries"]))
        self.assertTrue((input_root / "release" / "bin" / "platformctl").is_file())
        agent_unit = (input_root / "services" / "vitalserver-host-agent.service").read_text(encoding="utf-8")
        self.assertIn("RuntimeDirectory=vitalserver-runtime-platform", agent_unit)
        self.assertIn("ExecStart=" + self.current + "/bin/host-agent --deployment-configuration", agent_unit)
        composition = linux_host_package_composer._parse_arguments(["--composition", result["linuxHostPackageCompositionPath"]])
        package = linux_host_package_composer.compose_linux_host_package(composition)
        self.assertTrue(Path(package["artifactPath"]).is_file())
        self.assertEqual("vitalserver-runtime-platform_0.2.0-dev_amd64.deb", Path(package["artifactPath"]).name)

    def test_rejects_a_deployment_that_does_not_name_the_packaged_provider_bridge(self) -> None:
        document = json.loads(self.host_agent.read_text(encoding="utf-8"))
        document["provider"]["nativeProviderBridgeExecutablePath"] = self.current + "/bin/another-bridge"
        self.host_agent.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaisesRegex(preparer.LinuxHostReleaseInputPreparationError, "packaged Linux provider bridge path"):
            preparer.prepare_linux_host_release_input(self.preparation())
        self.assertFalse((self.release_root / preparer.RELEASE_INPUT_DIRECTORY_NAME).exists())

    def test_rejects_a_socket_outside_the_declared_systemd_runtime_directory(self) -> None:
        document = json.loads(self.host_agent.read_text(encoding="utf-8"))
        document["control"]["localAdministration"]["endpointAddress"] = "/tmp/host-agent.sock"
        self.host_agent.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaisesRegex(preparer.LinuxHostReleaseInputPreparationError, "RuntimeDirectory"):
            preparer.prepare_linux_host_release_input(self.preparation())

    def test_checked_in_linux_reference_profile_forms_a_valid_release_input(self) -> None:
        profile = Path(__file__).resolve().parents[2] / "product" / "deployment-profiles" / "linux-kvm-libvirt-systemd-external-guest-external-vitalserver-reference"
        result = preparer.prepare_linux_host_release_input(replace(
            self.preparation(),
            host_agent_deployment_configuration=profile / "host-agent-deployment-configuration.v1.json",
            host_edge_proxy_deployment_configuration=profile / "host-edge-proxy-deployment-configuration.v1.json",
            host_update_handoff_supervisor_configuration=profile / "host-update-handoff-supervisor-configuration.v1.json",
            operator_interface_bootstrap_configuration=profile / "operator-interface-bootstrap-configuration.v1.json",
            host_update_trust_store=profile / "update-trust-store.v1.json",
        ))
        self.assertTrue(Path(result["installationManifestPath"]).is_file())


if __name__ == "__main__":
    unittest.main()
