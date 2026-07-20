"""Black-box Recorder Gateway acceptance proof through public contracts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import unittest

from tooling.contracts import ContractRepository


ROOT = Path(__file__).resolve().parents[2]
GATEWAY = ROOT / "services" / "recorder-gateway"
NODE = os.environ.get("RUNTIME_PLATFORM_NODE", "node")
NPM = os.environ.get("RUNTIME_PLATFORM_NPM", "npm")


class RecorderGatewayAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = ContractRepository(ROOT)
        cls.contracts.load()
        # The acceptance fixture builds TypeScript before it starts the public
        # Recorder protocol scenario. It therefore declares development tools
        # as an input rather than inheriting an ambient npm production/omit
        # policy that would make the same command unavailable.
        for command in ([NPM, "ci", "--include=dev"], [NPM, "run", "build"]):
            completed = subprocess.run(command, cwd=GATEWAY, capture_output=True, text=True, check=False)
            if completed.returncode != 0:
                raise AssertionError("Gateway command failed: {0}\n{1}\n{2}".format(" ".join(command), completed.stdout, completed.stderr))

    def test_socketio_v2_durable_ingress_and_delivery_receipts(self) -> None:
        completed = subprocess.run(
            [NODE, str(ROOT / "acceptance" / "harness" / "recorder_gateway_scenario.mjs")],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        scenario = json.loads(completed.stdout)

        ingress_result = scenario["ingressResult"]
        delivery_result = scenario["deliveryResult"]
        self.assertEqual("available", ingress_result["state"], ingress_result)
        self.assertEqual("available", delivery_result["state"], delivery_result)
        self.assertEqual([], self.contracts.validate_instance("ingress-receipt.schema.json", ingress_result["value"]))
        self.assertEqual([], self.contracts.validate_instance("delivery-receipt.schema.json", delivery_result["value"]))
        self.assertEqual("accepted", ingress_result["value"]["ingressState"])
        self.assertEqual("succeeded", delivery_result["value"]["outcome"]["state"])
        self.assertEqual("not-scheduled", delivery_result["value"]["retry"]["state"])
        self.assertEqual("vitalserver-acceptance-fixture", delivery_result["value"]["provider"]["id"])

        # Backpressure and session errors are protocol acknowledgements, not
        # synthetic C5 receipts; a retry/receipt exists only after admission.
        self.assertEqual("rejected", scenario["full"]["state"])
        self.assertEqual("vitalserver-delivery-replay-capacity-reached", scenario["full"]["issue"]["code"])
        self.assertNotIn("receiptId", scenario["full"])
        self.assertEqual("rejected", scenario["beforeJoin"]["state"])
        self.assertEqual("recorder-session-not-joined", scenario["beforeJoin"]["issue"]["code"])
        self.assertEqual("unsupported", scenario["command"]["state"])
        self.assertEqual("recorder-command-dispatch-not-enabled", scenario["command"]["issue"]["code"])
        self.assertNotEqual(scenario["joined"]["sessionId"], scenario["rejoined"]["sessionId"])
        self.assertEqual(4, scenario["vitalServerReceivedByteCount"])


if __name__ == "__main__":
    unittest.main()
