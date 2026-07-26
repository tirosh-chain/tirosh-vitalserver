"""Focused tests for quarantined reference-fixture verification."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tooling import reference_fixtures


class ReferenceFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.source_fixtures = cls.root / reference_fixtures.FIXTURE_ROOT

    def copied_root(self) -> tempfile.TemporaryDirectory[str]:
        temporary_directory = tempfile.TemporaryDirectory()
        root = Path(temporary_directory.name)
        target = root / reference_fixtures.FIXTURE_ROOT
        target.parent.mkdir(parents=True)
        shutil.copytree(self.source_fixtures, target)
        return temporary_directory

    def test_current_collection_has_no_findings(self) -> None:
        self.assertEqual([], reference_fixtures.validate(self.root))

    def test_rejects_a_changed_fixture_digest(self) -> None:
        with self.copied_root() as temporary_directory:
            root = Path(temporary_directory)
            fixture = root / reference_fixtures.FIXTURE_ROOT / "recorder-socketio/join-vr.json"
            fixture.write_text(fixture.read_text(encoding="utf-8") + "\n", encoding="utf-8")

            findings = reference_fixtures.validate(root)

        self.assertTrue(any(finding.code == "fixture-digest-mismatch" for finding in findings))

    def test_rejects_an_unregistered_json_fixture(self) -> None:
        with self.copied_root() as temporary_directory:
            root = Path(temporary_directory)
            fixture = root / reference_fixtures.FIXTURE_ROOT / "unregistered.json"
            fixture.write_text(
                json.dumps(
                    {
                        "schemaVersion": "v1",
                        "fixtureKind": "ingress-outcome-observation",
                        "expectedFact": {},
                    }
                ),
                encoding="utf-8",
            )

            findings = reference_fixtures.validate(root)

        self.assertTrue(any(finding.code == "fixture-unregistered" for finding in findings))

    def test_rejects_an_invalid_capture_date(self) -> None:
        with self.copied_root() as temporary_directory:
            root = Path(temporary_directory)
            manifest = root / reference_fixtures.FIXTURE_ROOT / reference_fixtures.MANIFEST_NAME
            document = json.loads(manifest.read_text(encoding="utf-8"))
            document["fixtures"][0]["capturedAt"] = "not-a-date"
            manifest.write_text(json.dumps(document), encoding="utf-8")

            findings = reference_fixtures.validate(root)

        self.assertTrue(any(finding.code == "fixture-captured-at-invalid" for finding in findings))

    def test_rejects_a_prohibited_raw_data_key(self) -> None:
        with self.copied_root() as temporary_directory:
            root = Path(temporary_directory)
            fixture = root / reference_fixtures.FIXTURE_ROOT / "recorder-socketio/join-vr.json"
            document = json.loads(fixture.read_text(encoding="utf-8"))
            document["rawPayload"] = "omitted"
            fixture.write_text(json.dumps(document), encoding="utf-8")

            findings = reference_fixtures.validate(root)

        self.assertTrue(any(finding.code == "fixture-prohibited-key" for finding in findings))


if __name__ == "__main__":
    unittest.main()
