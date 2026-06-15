import Contracts
import Foundation
import SQLite3
import Errors

extension SQLiteRuntimeObservabilityStore {
    public func append(_ observation: VitalDBObservationDocument) throws {
        try initialize()
        try database.withDatabase { db in
            try execute(db, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                let shouldProject = try !vitalDBObservationExists(observedAt: observation.observedAt, db: db)
                try insert(observation, db: db)
                if shouldProject {
                    try projectRecorderActivityBuckets(observation, db: db)
                    try projectRelationships(observation, db: db)
                }
                try execute(db, sql: "COMMIT")
            } catch {
                try rollbackTransactionAfterFailure(db, originalError: error)
            }
        }
    }

    public func loadLatestVitalDBObservation() throws -> VitalDBObservationDocument? {
        try database.withReadOnlyDatabase { db in
            let observations = try queryVitalDBObservations(
                db,
                sql: """
                SELECT payload_json
                FROM vitaldb_observation_snapshots
                ORDER BY observed_at DESC
                LIMIT 1
                """,
                bindings: []
            )
            return observations.first
        }
    }

    public func loadVitalDBObservations(limit: Int = 1000) throws -> [VitalDBObservationDocument] {
        guard limit > 0 else {
            return []
        }
        return try database.withReadOnlyDatabase { db in
            let observations = try queryVitalDBObservations(
                db,
                sql: """
                SELECT payload_json
                FROM vitaldb_observation_snapshots
                ORDER BY observed_at DESC
                LIMIT ?
                """,
                bindings: [.int(limit)]
            )
            return Array(observations.reversed())
        }
    }

    private func insert(_ observation: VitalDBObservationDocument, db: OpaquePointer) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = String(decoding: try encoder.encode(observation), as: UTF8.self)

        try execute(
            db,
            sql: """
            INSERT OR REPLACE INTO vitaldb_observation_snapshots(
              observed_at,
              ready,
              recorder_count,
              anomaly_count,
              payload_json
            ) VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(observation.observedAt),
                .int(observation.ready ? 1 : 0),
                .int(observation.recorders.count),
                .int(observation.anomalies.count),
                .text(payload),
            ]
        )
    }

    private func vitalDBObservationExists(observedAt: String, db: OpaquePointer) throws -> Bool {
        try containsRow(
            db,
            sql: "SELECT 1 FROM vitaldb_observation_snapshots WHERE observed_at = ? LIMIT 1",
            bindings: [.text(observedAt)]
        )
    }

    private func queryVitalDBObservations(
        _ db: OpaquePointer,
        sql: String,
        bindings: [SQLiteBinding]
    ) throws -> [VitalDBObservationDocument] {
        let decoder = JSONDecoder()
        return try queryRows(db, sql: sql, bindings: bindings) { statement in
            let payload = try requiredText(
                statement,
                0,
                table: "vitaldb_observation_snapshots",
                column: "payload_json"
            )
            guard let data = payload.data(using: .utf8) else {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(
                    payload: payload,
                    reason: "payload is not valid UTF-8"
                )
            }
            do {
                return try decoder.decode(VitalDBObservationDocument.self, from: data)
            } catch {
                throw SQLiteRuntimeObservabilityStoreError.decodeFailed(
                    payload: payload,
                    reason: String(describing: error)
                )
            }
        }
    }
}
