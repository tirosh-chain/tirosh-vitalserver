import SQLite3

enum SQLiteRuntimeObservabilitySchema {
    static func apply(
        _ db: OpaquePointer,
        version: Int,
        appliedAt: String
    ) throws {
        try execute(db, sql: "PRAGMA journal_mode=WAL")
        try execute(db, sql: "PRAGMA foreign_keys=ON")
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS schema_migrations (
          version integer primary key,
          applied_at text not null
        )
        """)
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS runtime_events (
          id text primary key,
          timestamp text not null,
          source text not null,
          event_type text not null,
          status text,
          previous_status text,
          operation text,
          message text,
          runtime_version text,
          payload_json text not null
        )
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_runtime_events_timestamp_id
          ON runtime_events(timestamp, id)
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_runtime_events_event_type_timestamp
          ON runtime_events(event_type, timestamp)
        """)
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS runtime_event_index_state (
          key text primary key,
          value text not null
        )
        """)
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS vitaldb_observation_snapshots (
          observed_at text primary key,
          ready integer not null,
          recorder_count integer not null,
          anomaly_count integer not null,
          payload_json text not null
        )
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_observation_snapshots_observed_at
          ON vitaldb_observation_snapshots(observed_at)
        """)
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS vitaldb_recorder_activity_buckets (
          vrcode text not null,
          bucket_started_at text not null,
          bucket_seconds integer not null,
          message_count integer not null,
          byte_count integer not null,
          room_count integer not null,
          first_observed_at text not null,
          last_observed_at text not null,
          primary key(vrcode, bucket_started_at, bucket_seconds)
        )
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_recorder_activity_buckets_time
          ON vitaldb_recorder_activity_buckets(bucket_started_at)
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_recorder_activity_buckets_vrcode_time
          ON vitaldb_recorder_activity_buckets(vrcode, bucket_started_at)
        """)
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS vitaldb_recorder_activity_ranges (
          vrcode text primary key,
          first_seen_at text,
          last_seen_at text,
          first_observed_at text not null,
          last_observed_at text not null
        )
        """)
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS vitaldb_bed_assignments (
          id text primary key,
          bed_id text not null,
          bed_name text,
          vrcode text not null,
          started_at text not null,
          ended_at text,
          last_seen_at text,
          last_observed_at text not null,
          status text not null,
          patient_connected integer,
          observation_count integer not null
        )
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_bed_assignments_bed_time
          ON vitaldb_bed_assignments(bed_id, started_at)
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_bed_assignments_vrcode_time
          ON vitaldb_bed_assignments(vrcode, started_at)
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_bed_assignments_open
          ON vitaldb_bed_assignments(bed_id, ended_at)
        """)
        try execute(db, sql: """
        CREATE TABLE IF NOT EXISTS vitaldb_relationship_events (
          id text primary key,
          observed_at text not null,
          event_type text not null,
          severity text not null,
          bed_id text,
          bed_name text,
          vrcode text,
          previous_vrcode text,
          previous_bed_id text,
          message text not null
        )
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_relationship_events_observed_at
          ON vitaldb_relationship_events(observed_at)
        """)
        try execute(db, sql: """
        CREATE INDEX IF NOT EXISTS idx_vitaldb_relationship_events_type_time
          ON vitaldb_relationship_events(event_type, observed_at)
        """)
        try execute(
            db,
            sql: "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (?, ?)",
            bindings: [.int(version), .text(appliedAt)]
        )
    }
}
