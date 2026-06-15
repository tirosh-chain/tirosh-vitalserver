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
                WITH bucket_bounds AS (
                  SELECT vrcode,
                         min(bucket_started_at) AS first_bucket_started_at,
                         max(bucket_started_at) AS latest_bucket_started_at
                  FROM vitaldb_recorder_activity_buckets
                  WHERE vrcode = ?
                  GROUP BY vrcode
                )
                SELECT bucket_bounds.vrcode,
                       bucket_bounds.first_bucket_started_at,
                       bucket_bounds.latest_bucket_started_at,
                       ranges.first_seen_at,
                       ranges.last_seen_at
                FROM bucket_bounds
                LEFT JOIN vitaldb_recorder_activity_ranges ranges
                  ON ranges.vrcode = bucket_bounds.vrcode
                """,
                bindings: [.text(vrcode)]
            ) { statement in
                let vrcode = try requiredText(
                    statement,
                    0,
                    table: "vitaldb_recorder_activity_buckets",
                    column: "vrcode"
                )
                let firstActivityStartedAt = try requiredText(
                    statement,
                    1,
                    table: "vitaldb_recorder_activity_buckets",
                    column: "first_bucket_started_at"
                )
                let latestActivityStartedAt = try requiredText(
                    statement,
                    2,
                    table: "vitaldb_recorder_activity_buckets",
                    column: "latest_bucket_started_at"
                )
                return VitalDBRecorderActivityBucketBounds(
                    vrcode: vrcode,
                    firstBucketStartedAt: earliestActivityTimestamp(
                        columnText(statement, 3),
                        firstActivityStartedAt
                    ) ?? firstActivityStartedAt,
                    latestBucketStartedAt: latestActivityTimestamp(
                        columnText(statement, 4),
                        latestActivityStartedAt
                    ) ?? latestActivityStartedAt
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
            try upsertRecorderActivityRange(
                vrcode: recorder.vrcode,
                firstSeenAt: activity.firstSeenAt,
                lastSeenAt: activity.lastSeenAt,
                observedAt: observation.observedAt,
                db: db
            )
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

    private func upsertRecorderActivityRange(
        vrcode: String,
        firstSeenAt: String?,
        lastSeenAt: String?,
        observedAt: String,
        db: OpaquePointer
    ) throws {
        guard firstSeenAt != nil || lastSeenAt != nil else {
            return
        }
        let existing = try queryRows(
            db,
            sql: """
            SELECT first_seen_at, last_seen_at, first_observed_at, last_observed_at
            FROM vitaldb_recorder_activity_ranges
            WHERE vrcode = ?
            LIMIT 1
            """,
            bindings: [.text(vrcode)]
        ) { statement in
            SQLiteVitalDBRecorderActivityRangeRow(
                firstSeenAt: columnText(statement, 0),
                lastSeenAt: columnText(statement, 1),
                firstObservedAt: try requiredText(
                    statement,
                    2,
                    table: "vitaldb_recorder_activity_ranges",
                    column: "first_observed_at"
                ),
                lastObservedAt: try requiredText(
                    statement,
                    3,
                    table: "vitaldb_recorder_activity_ranges",
                    column: "last_observed_at"
                )
            )
        }.first

        try execute(
            db,
            sql: """
            INSERT INTO vitaldb_recorder_activity_ranges(
              vrcode,
              first_seen_at,
              last_seen_at,
              first_observed_at,
              last_observed_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(vrcode) DO UPDATE SET
              first_seen_at = excluded.first_seen_at,
              last_seen_at = excluded.last_seen_at,
              first_observed_at = excluded.first_observed_at,
              last_observed_at = excluded.last_observed_at
            """,
            bindings: [
                .text(vrcode),
                .optionalText(earliestActivityTimestamp(existing?.firstSeenAt, firstSeenAt)),
                .optionalText(latestActivityTimestamp(existing?.lastSeenAt, lastSeenAt)),
                .text(earliestActivityTimestamp(existing?.firstObservedAt, observedAt) ?? observedAt),
                .text(latestActivityTimestamp(existing?.lastObservedAt, observedAt) ?? observedAt),
            ]
        )
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

private struct SQLiteVitalDBRecorderActivityRangeRow {
    let firstSeenAt: String?
    let lastSeenAt: String?
    let firstObservedAt: String
    let lastObservedAt: String
}

private func earliestActivityTimestamp(_ left: String?, _ right: String?) -> String? {
    activityTimestampBoundary(left, right, orderedBefore: <)
}

private func latestActivityTimestamp(_ left: String?, _ right: String?) -> String? {
    activityTimestampBoundary(left, right, orderedBefore: >)
}

private func activityTimestampBoundary(
    _ left: String?,
    _ right: String?,
    orderedBefore: (Date, Date) -> Bool
) -> String? {
    guard let left else {
        return right
    }
    guard let right else {
        return left
    }
    guard let leftDate = sqliteActivityDate(from: left) else {
        return left
    }
    guard let rightDate = sqliteActivityDate(from: right) else {
        return right
    }
    return orderedBefore(rightDate, leftDate) ? right : left
}

private func sqliteActivityDate(from value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}
