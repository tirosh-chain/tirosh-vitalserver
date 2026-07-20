from __future__ import annotations

from pathlib import Path
import unittest

from tooling import product_delivery_release_plan as plans


class ProductDeliveryReleasePlanTests(unittest.TestCase):
    @property
    def release_delivery_plans_document(self) -> Path:
        return Path(__file__).resolve().parents[2] / "product" / "delivery" / "release-delivery-plans.v1.json"

    def test_projects_the_selected_windows_msi_identity_and_every_scm_registration(self) -> None:
        plan = plans.load_selected_windows_host_msi_release_plan(
            self.release_delivery_plans_document,
            "windows-runtime-platform-release",
        )
        self.assertEqual("0.2.0", plan.product_version)
        self.assertEqual("VitalServerRuntimePlatform-0.2.0.msi", plan.expected_msi_file_name)
        self.assertEqual("VitalServerHostAgent", plan.host_agent_windows_scm_service_name)
        self.assertEqual("VitalServerHostEdgeProxy", plan.host_edge_proxy_windows_scm_service_name)
        self.assertEqual("VitalServerHostUpdateHandoffSupervisor", plan.host_update_handoff_supervisor_windows_scm_service_name)

    def test_projects_the_selected_macos_pkg_identity_and_explicit_signature_policy(self) -> None:
        plan = plans.load_selected_macos_host_package_release_plan(
            self.release_delivery_plans_document,
            "macos-runtime-platform-release",
        )
        self.assertEqual("0.2.0-dev", plan.product_version)
        self.assertEqual("VitalServerRuntimePlatform-0.2.0-dev.pkg", plan.expected_package_file_name)
        self.assertEqual("com.tirosh.vitalserver.runtime-platform", plan.macos_installer_package_identifier)
        self.assertEqual("unsigned", plan.macos_installer_signature_policy)

    def test_projects_the_selected_linux_deb_identity_and_every_systemd_registration(self) -> None:
        plan = plans.load_selected_linux_host_deb_release_plan(
            self.release_delivery_plans_document,
            "linux-runtime-platform-release",
        )
        self.assertEqual("0.2.0-dev", plan.product_version)
        self.assertEqual("vitalserver-runtime-platform_0.2.0-dev_amd64.deb", plan.expected_deb_file_name)
        self.assertEqual("vitalserver-host-agent.service", plan.host_agent_systemd_service_name)
        self.assertEqual("vitalserver-host-edge-proxy.service", plan.host_edge_proxy_systemd_service_name)
        self.assertEqual("vitalserver-host-update-handoff-supervisor.service", plan.host_update_handoff_supervisor_systemd_service_name)

    def test_rejects_projecting_a_plan_for_the_wrong_platform(self) -> None:
        with self.assertRaisesRegex(plans.ProductDeliveryReleasePlanError, "target windows"):
            plans.load_selected_windows_host_msi_release_plan(
                self.release_delivery_plans_document,
                "linux-runtime-platform-release",
            )


if __name__ == "__main__":
    unittest.main()
