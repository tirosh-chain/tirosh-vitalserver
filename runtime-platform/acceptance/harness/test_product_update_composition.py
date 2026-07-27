"""Black-box proof for one complete Product update release bundle.

The test composes Container, Guest Runtime, and Host Platform artifacts and
sends the resulting Product Update Specification through the generic bootstrap
envelope signer. It deliberately stops before activation: the installed
layer-specific managers own those runtime operations.
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


class ProductUpdateCompositionAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.work = Path(cls.temporary_directory.name)
        cls.archive_composer = cls.work / "guest-product-release-archive-composer"
        cls.composer = cls.work / "product-update-composer"
        cls.signer = cls.work / "release-composer"
        cls.build(ROOT / "tooling" / "guest-product-release-archive-composer", "./cmd/guest-product-release-archive-composer", cls.archive_composer)
        cls.build(ROOT / "tooling" / "product-update-composer", "./cmd/product-update-composer", cls.composer)
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

    def test_complete_product_update_becomes_signed_bundle(self) -> None:
        updater = self.write_artifact("host-updater", b"next-updater", executable=True)
        container_executor = self.write_artifact("bundled-upstream-effect-executor", b"container-effect-executor", executable=True)
        guest_executor = self.write_artifact("guest-product-release-effect-executor", b"guest-effect-executor", executable=True)
        host_executor = self.write_artifact("host-platform-release-effect-executor", b"host-effect-executor", executable=True)
        container_apply = self.write_artifact("bundled-upstream-030.tar.gz", b"bundled-upstream-030")
        apply_archive = self.compose_release_archive("0.3.0", b"guest-runtime-030")
        rollback_archive = self.compose_release_archive("0.2.0", b"guest-runtime-020")
        host_apply = self.write_artifact("host-platform-030.tar.gz", b"host-platform-030")
        host_rollback = self.write_artifact("host-platform-020.tar.gz", b"host-platform-020")
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
            "guestRuntime": {
                "productRelease": {
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
                    "executor": {"id": "guest-product-release-effect-executor-030", "sourcePath": str(guest_executor)},
                    "configurationArtifactId": "guest-product-release-effect-executor-configuration-030",
                    "guestProductReleaseManagerPort": 18444,
                    "requestTimeoutMilliseconds": 600000,
                },
            },
            "bundledUpstreamImageSet": {
                "apply": {
                    "expectedActiveImageSet": {"state": "unprovisioned"},
                    "targetImageSetId": "bundled-upstream-030",
                    "artifact": {"id": "bundled-upstream-image-set-030", "sourcePath": str(container_apply)},
                },
                "effectExecutor": {
                    "executor": {"id": "bundled-upstream-effect-executor-030", "sourcePath": str(container_executor)},
                    "configurationArtifactId": "bundled-upstream-effect-configuration-030",
                    "imageSetManagerPort": 18445,
                    "requestTimeoutMilliseconds": 600000,
                },
            },
            "hostPlatformRelease": {
                "apply": {
                    "expectedActiveReleaseId": "runtime-platform-020",
                    "targetReleaseId": "runtime-platform-030",
                    "artifact": {"id": "host-platform-release-030", "sourcePath": str(host_apply)},
                },
                "rollback": {
                    "expectedActiveReleaseId": "runtime-platform-030",
                    "targetReleaseId": "runtime-platform-020",
                    "artifact": {"id": "host-platform-release-020", "sourcePath": str(host_rollback)},
                },
                "effectExecutor": {
                    "executor": {"id": "host-platform-release-effect-executor-030", "sourcePath": str(host_executor)},
                    "configurationArtifactId": "host-platform-release-effect-configuration-030",
                    "requestTimeoutMilliseconds": 300000,
                },
            },
        }
        composition_path = self.test_work / "product-update-composition.json"
        composition_path.write_text(json.dumps(source), encoding="utf-8")
        prepared = self.test_work / "prepared"
        composed = subprocess.run([str(self.composer), "--composition", str(composition_path), "--output-directory", str(prepared)], capture_output=True, text=True, check=False)
        self.assertEqual(composed.returncode, 0, composed.stderr)
        result = json.loads(composed.stdout)
        specification = json.loads(Path(result["productUpdateSpecificationPath"]).read_text(encoding="utf-8"))
        self.assertEqual([layer["layer"] for layer in specification["layerPlan"]], ["container", "guest-runtime", "host-platform"])
        guest_layer = specification["layerPlan"][1]
        host_layer = specification["layerPlan"][2]
        self.assertEqual(guest_layer["artifact"]["relativePath"], "payload/guest-product-releases/vitalserver-guest-product-0.3.0.tar.gz")
        self.assertEqual(guest_layer["rollback"]["artifact"]["relativePath"], "payload/guest-product-releases/vitalserver-guest-product-0.2.0.tar.gz")
        self.assertEqual(host_layer["dependsOn"], ["guest-runtime"])
        self.assertEqual(host_layer["artifact"]["relativePath"], "payload/host-platform-releases/runtime-platform-030.tar.gz")
        self.assertEqual(host_layer["rollback"]["artifact"]["relativePath"], "payload/host-platform-releases/runtime-platform-020.tar.gz")
        configuration = json.loads(Path(result["effectConfigurationPath"]).read_text(encoding="utf-8"))
        self.assertEqual(configuration["guestProductReleaseManagerEndpoint"], {"scheme": "http", "host": "127.0.0.1", "port": 18444, "path": "/v1/guest-product-release-updates", "requestTimeoutMilliseconds": 600000})
        self.assertEqual(configuration["rollback"]["targetReleaseId"], "vitalserver-guest-product-0.2.0")
        host_configuration = json.loads(Path(result["hostPlatformEffectConfigurationPath"]).read_text(encoding="utf-8"))
        self.assertEqual(host_configuration["hostInstallationManager"]["executablePath"], "/Library/Application Support/VitalServerRuntimePlatform/current/bin/host-installation-manager")
        self.assertEqual(host_configuration["apply"], {"expectedActiveReleaseId": "runtime-platform-020", "targetReleaseId": "runtime-platform-030"})

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
        self.assertEqual(envelope["layerOrder"], ["container", "guest-runtime", "host-platform"])
        self.assertTrue((bundle / "payload" / "effect-configurations" / "guest-product-release-effect-executor-configuration-030.json").is_file())
        self.assertTrue((bundle / "payload" / "effect-configurations" / "host-platform-release-effect-configuration-030.json").is_file())
        self.assertTrue((bundle / "payload" / "guest-product-releases" / "vitalserver-guest-product-0.3.0.tar.gz").is_file())
        self.assertTrue((bundle / "payload" / "host-platform-releases" / "runtime-platform-030.tar.gz").is_file())

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
