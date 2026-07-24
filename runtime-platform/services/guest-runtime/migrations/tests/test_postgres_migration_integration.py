from __future__ import annotations

import os
from pathlib import Path
import unittest


TEST_DATABASE_URL = os.environ.get(
    "VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL"
)


@unittest.skipUnless(
    TEST_DATABASE_URL,
    "VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL is not configured",
)
class RecorderCatalogPostgreSQLMigrationIntegrationTests(unittest.TestCase):
    def test_head_is_idempotent_and_owner_constraints_are_live(self) -> None:
        from alembic import command
        from alembic.config import Config
        import psycopg
        from psycopg.errors import CheckViolation

        migrations = Path(__file__).parents[1]
        previous_url = os.environ.get(
            "VITALSERVER_RECORDER_CATALOG_DATABASE_URL"
        )
        os.environ["VITALSERVER_RECORDER_CATALOG_DATABASE_URL"] = str(
            TEST_DATABASE_URL
        )
        try:
            config = Config(str(migrations / "alembic.ini"))
            command.upgrade(config, "head")
            command.upgrade(config, "head")
        finally:
            if previous_url is None:
                os.environ.pop(
                    "VITALSERVER_RECORDER_CATALOG_DATABASE_URL", None
                )
            else:
                os.environ[
                    "VITALSERVER_RECORDER_CATALOG_DATABASE_URL"
                ] = previous_url

        psycopg_url = str(TEST_DATABASE_URL).replace(
            "postgresql+psycopg://", "postgresql://", 1
        )
        with psycopg.connect(psycopg_url) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT version_num FROM alembic_version")
                self.assertEqual(
                    "0006_backup_owner",
                    cursor.fetchone()[0],
                )
                cursor.execute(
                    """
                    SELECT schemaname, tablename
                      FROM pg_catalog.pg_tables
                     WHERE schemaname IN (
                       'recorder_catalog',
                       'archive_export',
                       'recorder_assignment',
                       'guest_operational_state'
                     )
                    """
                )
                tables = set(cursor.fetchall())
                self.assertTrue(
                    {
                        ("recorder_catalog", "admission_requests"),
                        ("recorder_catalog", "observations"),
                        ("recorder_catalog", "recorder_current"),
                        ("recorder_catalog", "expectation_events"),
                        ("recorder_catalog", "recorder_expectations"),
                        ("archive_export", "artifacts"),
                        ("archive_export", "recorder_attributions"),
                        ("archive_export", "upload_attempts"),
                        ("archive_export", "indexing_receipts"),
                        ("archive_export", "source_admission_requests"),
                        ("recorder_assignment", "evidence"),
                        ("recorder_assignment", "resolutions"),
                        ("guest_operational_state", "metadata"),
                    }.issubset(tables)
                )
                cursor.execute(
                    """
                    SELECT database_id, backup_contract_version
                      FROM guest_operational_state.metadata
                     WHERE singleton = true
                    """
                )
                database_id, backup_contract_version = cursor.fetchone()
                self.assertTrue(
                    database_id.startswith("guest-postgresql-")
                )
                self.assertEqual("v1", backup_contract_version)
                cursor.execute(
                    """
                    INSERT INTO archive_export.artifacts (
                      artifact_id,
                      source_kind,
                      source_receipt_type,
                      source_receipt_id,
                      manifest_id,
                      original_file_name,
                      media_type,
                      byte_size,
                      sha256,
                      finalization_state,
                      manifest_document,
                      created_at,
                      finalized_at
                    ) VALUES (
                      'integration-artifact',
                      'recorder-upload',
                      'gateway-upload-receipt',
                      'integration-upload-receipt',
                      'integration-manifest',
                      'integration.vital',
                      'application/octet-stream',
                      1,
                      repeat('a', 64),
                      'finalized',
                      '{}'::jsonb,
                      CURRENT_TIMESTAMP,
                      CURRENT_TIMESTAMP
                    )
                    """
                )
                with self.assertRaises(CheckViolation):
                    with connection.transaction():
                        cursor.execute(
                            """
                            INSERT INTO archive_export.recorder_attributions (
                              artifact_id,
                              evidence_observed_at,
                              outcome,
                              policy_version,
                              resolved_at
                            ) VALUES (
                              'integration-artifact',
                              CURRENT_TIMESTAMP,
                              'matched',
                              'v1',
                              CURRENT_TIMESTAMP
                            )
                            """
                        )
            connection.rollback()


if __name__ == "__main__":
    unittest.main()
