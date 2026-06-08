import Contracts
import Foundation
import SQLite3

extension SQLiteRuntimeObservabilityStore {
    public func loadVitalDBRecorderActivityBuckets(
        query: VitalDBRecorderActivityBucketQuery = VitalDBRecorderActivityBucketQuery()
    ) throws -> [VitalDBRecorderActivityBucketRecord] {
        guard query.limit > 0 else {
            return []
        }
        return try database.withReadOnlyDatabase { db in
            var predicates: [String] = []
            var bindings: [SQLiteBinding] = []
            if let vrcode = query.vrcode {
                predicates.append("vrcode = ?")
                bindings.append(.text(vrcode))
            }
            if let since = query.since {
                predicates.append("bucket_started_at >= ?")
                bindings.append(.text(since))
            }
            if let until = query.until {
                predicates.append("bucket_started_at <= ?")
                bindings.append(.text(until))
            }
            let whereClause = predicates.isEmpty ? "" : "WHERE \(predicates.joined(separator: " AND "))"
            bindings.append(.int(query.limit))
            let records = try queryRecorderActivityBuckets(
                db,
                sql: """
                SELECT vrcode, bucket_started_at, bucket_seconds,
                       message_count, byte_count, room_count,
                       first_observed_at, last_observed_at
                FROM vitaldb_recorder_activity_buckets
                \(whereClause)
                ORDER BY bucket_started_at DESC, vrcode DESC
                LIMIT ?
                """,
                bindings: bindings
            )
            return Array(records.reversed())
        }
    }

    public func loadVitalDBRecorderActivityBucketBounds(
        vrcode: String
    ) throws -> VitalDBRecorderActivityBucketBounds? {
        guard !vrcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try database.withReadOnlyDatabase { db in
            try queryRows(
                db,
                sql: """
                SELECT vrcode, min(bucket_started_at), max(bucket_started_at)
                FROM vitaldb_recorder_activity_buckets
                WHERE vrcode = ?
                GROUP BY vrcode
                LIMIT 1
                """,
                bindings: [.text(vrcode)]
            ) { statement in
                let vrcode = try requiredText(
                    statement,
                    0,
                    table: "vitaldb_recorder_activity_buckets",
                    column: "vrcode"
                )
                let firstBucketStartedAt = try requiredText(
                    statement,
                    1,
                    table: "vitaldb_recorder_activity_buckets",
                    column: "min(bucket_started_at)"
                )
                let latestBucketStartedAt = try requiredText(
                    statement,
                    2,
                    table: "vitaldb_recorder_activity_buckets",
                    column: "max(bucket_started_at)"
                )
                return VitalDBRecorderActivityBucketBounds(
                    vrcode: vrcode,
                    firstBucketStartedAt: firstBucketStartedAt,
                    latestBucketStartedAt: latestBucketStartedAt
                )
            }.first
        }
    }

    func projectRecorderActivityBuckets(
        _ observation: VitalDBObservationDocument,
        db: OpaquePointer
    ) throws {
        for recorder in observation.recorders {
            guard let activity = recorder.activity else {
                continue
            }
            for bucket in activity.buckets {
                try upsertRecorderActivityBucket(
                    vrcode: recorder.vrcode,
                    bucket: bucket,
                    observedAt: observation.observedAt,
                    db: db
                )
            }
        }
    }

    private func upsertRecorderActivityBucket(
        vrcode: String,
        bucket: VitalDBRecorderActivityBucket,
        observedAt: String,
        db: OpaquePointer
    ) throws {
        try execute(
            db,
            sql: """
            INSERT INTO vitaldb_recorder_activity_buckets(
              vrcode,
              bucket_started_at,
              bucket_seconds,
              message_count,
              byte_count,
              room_count,
              first_observed_at,
              last_observed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(vrcode, bucket_started_at, bucket_seconds) DO UPDATE SET
              message_count = max(message_count, excluded.message_count),
              byte_count = max(byte_count, excluded.byte_count),
              room_count = max(room_count, excluded.room_count),
              first_observed_at = min(first_observed_at, excluded.first_observed_at),
              last_observed_at = max(last_observed_at, excluded.last_observed_at)
            """,
            bindings: [
                .text(vrcode),
                .text(bucket.bucketStartedAt),
                .int(bucket.bucketSeconds),
                .int(bucket.messageCount),
                .int(bucket.byteCount),
                .int(bucket.roomCount),
                .text(observedAt),
                .text(observedAt),
            ]
        )
    }

    private func queryRecorderActivityBuckets(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBRecorderActivityBucketRecord] {
        try queryRows(db, sql: sql, bindings: bindings) { statement in
            let vrcode = try requiredText(statement, 0, table: "vitaldb_recorder_activity_buckets", column: "vrcode")
            let bucketStartedAt = try requiredText(
                statement,
                1,
                table: "vitaldb_recorder_activity_buckets",
                column: "bucket_started_at"
            )
            let firstObservedAt = try requiredText(
                statement,
                6,
                table: "vitaldb_recorder_activity_buckets",
                column: "first_observed_at"
            )
            let lastObservedAt = try requiredText(
                statement,
                7,
                table: "vitaldb_recorder_activity_buckets",
                column: "last_observed_at"
            )
            return VitalDBRecorderActivityBucketRecord(
                vrcode: vrcode,
                bucketStartedAt: bucketStartedAt,
                bucketSeconds: Int(sqlite3_column_int(statement, 2)),
                messageCount: Int(sqlite3_column_int(statement, 3)),
                byteCount: Int(sqlite3_column_int(statement, 4)),
                roomCount: Int(sqlite3_column_int(statement, 5)),
                firstObservedAt: firstObservedAt,
                lastObservedAt: lastObservedAt
            )
        }
    }
}
