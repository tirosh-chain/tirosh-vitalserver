from __future__ import annotations

import ast
import unittest
from pathlib import Path


class RecorderCatalogMigrationContractTests(unittest.TestCase):
    def test_revision_chain_is_explicit_and_downgrades_are_not_destructive(self) -> None:
        versions = Path(__file__).parents[1] / "versions"
        expected = [
            (
                "0001_recorder_catalog_foundation.py",
                "0001_catalog_foundation",
                None,
            ),
            (
                "0002_recorder_catalog_expectations.py",
                "0002_catalog_expectations",
                "0001_catalog_foundation",
            ),
            (
                "0003_archive_export_lineage.py",
                "0003_archive_lineage",
                "0002_catalog_expectations",
            ),
            (
                "0004_archive_source_admissions.py",
                "0004_archive_source_admissions",
                "0003_archive_lineage",
            ),
            (
                "0005_recorder_assignment_owner.py",
                "0005_recorder_assignment_owner",
                "0004_archive_source_admissions",
            ),
            (
                "0006_guest_operational_state_backup_owner.py",
                "0006_backup_owner",
                "0005_recorder_assignment_owner",
            ),
        ]
        for filename, revision, down_revision in expected:
            source = (versions / filename).read_text(encoding="utf-8")
            tree = ast.parse(source)
            assignments = {
                node.targets[0].id: ast.literal_eval(node.value)
                for node in tree.body
                if isinstance(node, ast.Assign)
                and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id in {"revision", "down_revision"}
            }
            self.assertEqual(revision, assignments["revision"])
            self.assertEqual(down_revision, assignments["down_revision"])
            self.assertIn("raise RuntimeError", source)

    def test_owner_tables_and_attribution_invariants_are_declared(self) -> None:
        versions = Path(__file__).parents[1] / "versions"
        source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(versions.glob("*.py"))
        )
        for declaration in (
            "CREATE SCHEMA recorder_catalog",
            "CREATE TABLE recorder_catalog.admission_requests",
            "CREATE TABLE recorder_catalog.observations",
            "CREATE TABLE recorder_catalog.recorder_current",
            "CREATE TABLE recorder_catalog.expectation_events",
            "CREATE TABLE recorder_catalog.recorder_expectations",
            "CREATE SCHEMA archive_export",
            "CREATE TABLE archive_export.artifacts",
            "CREATE TABLE archive_export.recorder_attributions",
            "CREATE TABLE archive_export.upload_attempts",
            "CREATE TABLE archive_export.indexing_receipts",
            "CREATE TABLE archive_export.source_admission_requests",
            "CREATE SCHEMA recorder_assignment",
            "CREATE TABLE recorder_assignment.evidence",
            "CREATE TABLE recorder_assignment.resolutions",
            "CREATE SCHEMA guest_operational_state",
            "CREATE TABLE guest_operational_state.metadata",
        ):
            self.assertIn(declaration, source)
        self.assertIn("'matched', 'unresolved', 'ambiguous'", source)
        self.assertIn("'recorder-upload'", source)
        self.assertIn("'gateway-cold-path'", source)
        self.assertIn("outcome IN ('accepted', 'duplicate', 'quarantined')", source)
        self.assertIn("command_document jsonb NOT NULL", source)
        self.assertIn("command_digest char(64) NOT NULL", source)
        self.assertIn("event_document jsonb NOT NULL", source)
        self.assertIn("expectation_document jsonb NOT NULL", source)


if __name__ == "__main__":
    unittest.main()
