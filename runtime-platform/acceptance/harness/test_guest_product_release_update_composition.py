"""Black-box proof for the concrete Guest Product C61/C26 release path.

The test composes a release-specific payload and sends it through the generic
C25 signer. It deliberately stops before a Host/Guest activation: C59 owns
that runtime operation and requires a real macOS C32 provider bridge.
"""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
GO = os.environ.get("RUNTIME_PLATFORM_GO", "go")


class GuestProductReleaseUpdateCompositionAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.temporary_directory.name)
        cls.archive_composer = cls.work / "guest-product-release-archive-composer"
        cls.composer = cls.work / "guest-product-release-update-composer"
        cls.signer = cls.work / "release-composer"
        cls.build(ROOT / "tooling" / "guest-product-release-archive-composer", "./cmd/guest-product-release-archive-composer", cls.archive_composer)
        cls.build(ROOT / "tooling" / "guest-product-release-update-composer", "./cmd/guest-product-release-update-composer", cls.composer)
        cls.build(ROOT / "tooling" / "release-composer", "./cmd/release-composer", cls.signer)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def build(cls, directory: Path, package: str, output: Path) -> None:
        completed = subprocess.run([GO, "build", "-o", str(output), package], cwd=directory, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            raise AssertionError("build {0} failed:\n{1}\n{2}".format(package, completed.stdout, completed.stderr))

    def setUp(self) -> None:
        self.test_work = Path(tempfile.mkdtemp(dir=self.work, prefix="guest-product-release-update-"))
        self.artifacts = self.test_work / "artifacts"
        self.artifacts.mkdir()

    def write_artifact(self, name: str, contents: bytes, executable: bool = False) -> Path:
        path = self.artifacts / name
        path.write_bytes(contents)
        path.chmod(0o700 if executable else 0o600)
        return path

    def test_prepared_c61_c26_payload_becomes_signed_c25_bundle(self) -> None:
        updater = self.write_artifact("host-updater", b"next-updater", executable=True)
        executor = self.write_artifact("guest-product-release-effect-executor", b"c55-executor", executable=True)
        apply_archive = self.compose_release_archive("0.3.0", b"guest-runtime-030")
        rollback_archive = self.compose_release_archive("0.2.0", b"guest-runtime-020")
        source = {
            "schemaVersion": "v1",
            "bundleId": "release-bootstrap-030",
            "productId": "vitalserver-runtime-platform",
            "target": {"platform": "macos", "architecture": "arm64"},
            "targetRelease": {"productVersion": "0.3.0", "runtimeVersion": "0.3.0"},
            "signingKeyId": "release-key-2026",
            "issuedAt": "2026-07-20T00:00:00Z",
            "specificationId": "product-update-030",
            "nextUpdater": {"id": "host-updater-030", "sourcePath": str(updater)},
            "guestProductRelease": {
                "apply": {
                    "expectedActiveReleaseId": "vitalserver-guest-product-0.2.0",
                    "targetReleaseId": "vitalserver-guest-product-0.3.0",
                    "targetReleaseDirectory": "/opt/vitalserver/releases/vitalserver-guest-product-0.3.0",
                    "artifact": {"id": "guest-product-release-030", "sourcePath": str(apply_archive)},
                },
                "rollback": {
                    "expectedActiveReleaseId": "vitalserver-guest-product-0.3.0",
                    "targetReleaseId": "vitalserver-guest-product-0.2.0",
                    "targetReleaseDirectory": "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0",
                    "artifact": {"id": "guest-product-release-020", "sourcePath": str(rollback_archive)},
                },
            },
            "effectExecutor": {
                "executor": {"id": "guest-product-release-effect-executor-030", "sourcePath": str(executor)},
                "configurationArtifactId": "guest-product-release-effect-executor-configuration-030",
                "guestProductReleaseManagerPort": 18444,
                "requestTimeoutMilliseconds": 600000,
            },
        }
        composition_path = self.test_work / "guest-product-release-update-composition.json"
        composition_path.write_text(json.dumps(source), encoding="utf-8")
        prepared = self.test_work / "prepared"
        composed = subprocess.run([str(self.composer), "--composition", str(composition_path), "--output-directory", str(prepared)], capture_output=True, text=True, check=False)
        self.assertEqual(composed.returncode, 0, composed.stderr)
        result = json.loads(composed.stdout)
        specification = json.loads(Path(result["productUpdateSpecificationPath"]).read_text(encoding="utf-8"))
        layer = specification["layerPlan"][0]
        self.assertEqual(layer["layer"], "guest-runtime")
        self.assertEqual(layer["artifact"]["relativePath"], "payload/guest-product-releases/vitalserver-guest-product-0.3.0.tar.gz")
        self.assertEqual(layer["rollback"]["artifact"]["relativePath"], "payload/guest-product-releases/vitalserver-guest-product-0.2.0.tar.gz")
        configuration = json.loads(Path(result["effectConfigurationPath"]).read_text(encoding="utf-8"))
        self.assertEqual(configuration["guestProductReleaseManagerEndpoint"], {"scheme": "http", "host": "127.0.0.1", "port": 18444, "path": "/v1/guest-product-release-updates", "requestTimeoutMilliseconds": 600000})
        self.assertEqual(configuration["rollback"]["targetReleaseId"], "vitalserver-guest-product-0.2.0")

        signing_key = self.test_work / "release-key.base64"
        # A 64-byte Ed25519 private-key value is sufficient for this isolated
        # release-tool proof; production keys are C58-selected trust material.
        signing_key.write_text(base64.b64encode(b"r" * 64).decode("ascii"), encoding="ascii")
        signed_parent = self.test_work / "signed"
        signed_parent.mkdir()
        signed = subprocess.run(
            [
                str(self.signer),
                "--composition", result["releaseBundleCompositionPath"],
                "--payload-directory", result["payloadDirectory"],
                "--private-key", str(signing_key),
                "--output-directory", str(signed_parent),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(signed.returncode, 0, signed.stderr)
        bundle = Path(json.loads(signed.stdout)["BundleDirectory"])
        envelope = json.loads((bundle / "bootstrap-envelope.json").read_text(encoding="utf-8"))
        self.assertEqual(envelope["id"], "release-bootstrap-030")
        self.assertEqual(envelope["layerOrder"], ["guest-runtime"])
        self.assertTrue((bundle / "payload" / "effect-configurations" / "guest-product-release-effect-executor-configuration-030.json").is_file())
        self.assertTrue((bundle / "payload" / "guest-product-releases" / "vitalserver-guest-product-0.3.0.tar.gz").is_file())

    def compose_release_archive(self, version: str, runtime_contents: bytes) -> Path:
        source = self.test_work / ("guest-product-" + version)
        (source / "bin").mkdir(parents=True)
        runtime = source / "bin" / "guest-runtime"
        runtime.write_bytes(runtime_contents)
        runtime.chmod(0o755)
        (source / "bin" / "current-runtime").symlink_to("guest-runtime")
        output = self.test_work / ("guest-product-" + version + ".tar.gz")
        completed = subprocess.run(
            [str(self.archive_composer), "--release-source-directory", str(source), "--output-archive", str(output)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        archive = json.loads(completed.stdout)
        self.assertEqual(archive["archivePath"], str(output))
        self.assertEqual(archive["mediaType"], "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip")
        return output


if __name__ == "__main__":
    unittest.main()
