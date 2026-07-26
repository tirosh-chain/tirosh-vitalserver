"""C38 to systemd unit release-build adapter tests."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from tooling import guest_product_systemd_service_unit_composer as composer


class GuestProductSystemdServiceUnitComposerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.configuration_path = self.root / "guest-product-service-manager-deployment.json"
        self.configuration_path.write_text(
            json.dumps(self.valid_configuration()), encoding="utf-8"
        )
        self.unit_output_path = self.root / "vitalserver-guest-product.service"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    @staticmethod
    def valid_configuration() -> dict[str, object]:
        return {
            "schemaVersion": "v1",
            "serviceManagerKind": "systemd",
            "serviceUnitName": "vitalserver-guest-product.service",
            "supervisor": {
                "executablePath": "/opt/vitalserver/bin/guest-product-process-supervisor",
                "deploymentConfigurationPath": "/etc/vitalserver/guest-product-process-deployment.json",
            },
            "restart": {"mode": "on-failure", "delayMilliseconds": 1000},
            "logging": {
                "standardOutput": "journal+console",
                "standardError": "journal+console",
            },
            "install": {"wantedByTarget": "multi-user.target"},
        }

    def test_composes_one_explicit_systemd_unit_without_installing_it(self) -> None:
        result = composer.compose_guest_product_systemd_service_unit(
            self.configuration_path,
            self.unit_output_path,
        )

        self.assertEqual("vitalserver-guest-product.service", result["serviceUnitName"])
        self.assertEqual(
            """[Unit]
Description=VitalServer Guest Product Process Supervisor

[Service]
Type=simple
ExecStart=/opt/vitalserver/bin/guest-product-process-supervisor --deployment-configuration /etc/vitalserver/guest-product-process-deployment.json
Restart=on-failure
RestartSec=1s
StandardOutput=journal+console
StandardError=journal+console
KillMode=control-group

[Install]
WantedBy=multi-user.target
""",
            self.unit_output_path.read_text(encoding="utf-8"),
        )

    def test_rejects_missing_restart_policy_instead_of_selecting_one(self) -> None:
        configuration = self.valid_configuration()
        del configuration["restart"]
        self.configuration_path.write_text(json.dumps(configuration), encoding="utf-8")

        with self.assertRaisesRegex(
            composer.GuestProductSystemdServiceUnitCompositionError,
            "C38 deployment configuration is invalid",
        ):
            composer.compose_guest_product_systemd_service_unit(
                self.configuration_path,
                self.unit_output_path,
            )

    def test_rejects_missing_log_sink_instead_of_silencing_supervisor_failure(self) -> None:
        configuration = self.valid_configuration()
        del configuration["logging"]
        self.configuration_path.write_text(json.dumps(configuration), encoding="utf-8")

        with self.assertRaisesRegex(
            composer.GuestProductSystemdServiceUnitCompositionError,
            "C38 deployment configuration is invalid",
        ):
            composer.compose_guest_product_systemd_service_unit(
                self.configuration_path,
                self.unit_output_path,
            )

    def test_refuses_to_replace_an_existing_unit_output(self) -> None:
        self.unit_output_path.write_text("existing", encoding="utf-8")

        with self.assertRaisesRegex(
            composer.GuestProductSystemdServiceUnitCompositionError,
            "already exists",
        ):
            composer.compose_guest_product_systemd_service_unit(
                self.configuration_path,
                self.unit_output_path,
            )

    def test_refuses_unit_output_name_that_does_not_match_c38_service_name(self) -> None:
        with self.assertRaisesRegex(
            composer.GuestProductSystemdServiceUnitCompositionError,
            "must match C38 serviceUnitName",
        ):
            composer.compose_guest_product_systemd_service_unit(
                self.configuration_path,
                self.root / "guessed.service",
            )


if __name__ == "__main__":
    unittest.main()
