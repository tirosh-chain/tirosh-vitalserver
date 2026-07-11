from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile


ROOT = Path(__file__).resolve().parents[4]
TOOL = ROOT / "apps/vitalserver-platform-agent/packaging/linux/support-export-linux.py"


def test_linux_support_export_publishes_managed_artifact_evidence(tmp_path: Path) -> None:
    workflow = tmp_path / "run/platform-workflow.json"
    support = tmp_path / "support"
    operation_id = "workflow-0123456789abcdef0123456789abcdef"

    subprocess.run(
        [
            sys.executable,
            str(TOOL),
            "--operation-id",
            operation_id,
            "--operation-document",
            str(workflow),
            "--support-directory",
            str(support),
        ],
        check=True,
    )

    operation = json.loads(workflow.read_text(encoding="utf-8"))
    assert operation["state"] == "completed"
    assert operation["release"] is None
    assert operation["failure"] is None
    artifact = operation["artifact"]
    archive = Path(artifact["path"])
    assert archive.parent == support
    assert archive.stat().st_size == artifact["sizeBytes"]
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == artifact["sha256"]
    with tarfile.open(archive) as bundle:
        manifest = json.load(bundle.extractfile("vitalserver-support/manifest.json"))
    assert manifest["schemaVersion"] == 1
    assert manifest["operationId"] == operation_id
    assert "/etc/vitalserver/platform-agent.json" in manifest["excluded"]
    assert "/etc/vitalserver/secrets" in manifest["excluded"]
