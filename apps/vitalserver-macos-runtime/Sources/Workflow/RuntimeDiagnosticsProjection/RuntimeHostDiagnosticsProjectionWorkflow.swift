import Application
import Foundation

public struct RuntimeHostDiagnosticsProjectionResult: Equatable, Sendable {
    public let projectedEventCount: Int
    public let snapshotSourceSequence: Int

    public init(projectedEventCount: Int, snapshotSourceSequence: Int) {
        self.projectedEventCount = projectedEventCount
        self.snapshotSourceSequence = snapshotSourceSequence
    }
}

public struct RuntimeHostDiagnosticsProjectionFailure: Equatable, Sendable {
    public let projectionName: String
    public let sourceSequence: Int
    public let reason: String
    public let failureRecordingError: String?

    public init(
        projectionName: String,
        sourceSequence: Int,
        reason: String,
        failureRecordingError: String?
    ) {
        self.projectionName = projectionName
        self.sourceSequence = sourceSequence
        self.reason = reason
        self.failureRecordingError = failureRecordingError
    }
}

public enum RuntimeHostDiagnosticsProjectionWorkflowError:
    Error,
    Equatable,
    CustomStringConvertible
{
    case invalidBatchLimit(Int)
    case outboxReadFailed(String)
    case projectionFailed([RuntimeHostDiagnosticsProjectionFailure])

    public var description: String {
        switch self {
        case .invalidBatchLimit(let limit):
            return "Host diagnostics projection batch limit is invalid limit=\(limit)"
        case .outboxReadFailed(let reason):
            return "Host diagnostics outbox read failed reason=\(reason)"
        case .projectionFailed(let failures):
            return failures.map { failure in
                var text = "projection=\(failure.projectionName) sourceSequence=\(failure.sourceSequence) reason=\(failure.reason)"
                if let recordingError = failure.failureRecordingError {
                    text += " failureRecordingError=\(recordingError)"
                }
                return text
            }.joined(separator: "; ")
        }
    }
}

public struct RuntimeHostDiagnosticsProjectionWorkflow: @unchecked Sendable {
    private let repository: any RuntimeHostDiagnosticOutboxRepository
    private let eventSink: any RuntimeHostDiagnosticEventAppending
    private let snapshotSink: any RuntimeHostStateDiagnosticSnapshotWriting
    private let timestamp: () -> String
    private let describeError: (Error) -> String

    public init(
        repository: any RuntimeHostDiagnosticOutboxRepository,
        eventSink: any RuntimeHostDiagnosticEventAppending,
        snapshotSink: any RuntimeHostStateDiagnosticSnapshotWriting,
        timestamp: @escaping () -> String = {
            ISO8601DateFormatter().string(from: Date())
        },
        describeError: @escaping (Error) -> String
    ) {
        self.repository = repository
        self.eventSink = eventSink
        self.snapshotSink = snapshotSink
        self.timestamp = timestamp
        self.describeError = describeError
    }

    public func run(batchLimit: Int = 256) throws -> RuntimeHostDiagnosticsProjectionResult {
        guard batchLimit > 0 else {
            throw RuntimeHostDiagnosticsProjectionWorkflowError.invalidBatchLimit(batchLimit)
        }

        let pendingEvents: [RuntimeHostDiagnosticOutboxEvent]
        do {
            pendingEvents = try repository.loadPendingDiagnosticEvents(limit: batchLimit)
        } catch {
            throw RuntimeHostDiagnosticsProjectionWorkflowError.outboxReadFailed(
                describeError(error)
            )
        }

        var failures: [RuntimeHostDiagnosticsProjectionFailure] = []
        var projectedEventCount = 0
        for event in pendingEvents {
            do {
                try eventSink.appendDiagnosticEvent(event)
                try repository.markDiagnosticEventProjected(
                    sequence: event.sequence,
                    projectionName: RuntimeHostDiagnosticProjectionNames.eventLog,
                    projectedAt: timestamp()
                )
                projectedEventCount += 1
            } catch {
                failures.append(recordFailure(
                    projectionName: RuntimeHostDiagnosticProjectionNames.eventLog,
                    sourceSequence: event.sequence,
                    reason: describeError(error)
                ))
                break
            }
        }

        var snapshotSourceSequence = 0
        do {
            let snapshot = try repository.loadHostStateDiagnosticSnapshot(
                generatedAt: timestamp()
            )
            snapshotSourceSequence = snapshot.sourceSequence
            if let checkpoint = try repository.loadDiagnosticProjectionCheckpoint(
                projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot
            ), checkpoint.lastSequence > snapshot.sourceSequence {
                throw RuntimeHostDiagnosticsProjectionWorkflowError.projectionFailed([
                    RuntimeHostDiagnosticsProjectionFailure(
                        projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot,
                        sourceSequence: snapshot.sourceSequence,
                        reason: "snapshot checkpoint is ahead of SQLite source checkpoint=\(checkpoint.lastSequence)",
                        failureRecordingError: nil
                    )
                ])
            }
            try snapshotSink.writeHostStateDiagnosticSnapshot(snapshot)
            try repository.markDiagnosticSnapshotProjected(
                sourceSequence: snapshot.sourceSequence,
                projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot,
                projectedAt: timestamp()
            )
        } catch let error as RuntimeHostDiagnosticsProjectionWorkflowError {
            if case .projectionFailed(let checkpointFailures) = error {
                for checkpointFailure in checkpointFailures {
                    failures.append(recordFailure(
                        projectionName: checkpointFailure.projectionName,
                        sourceSequence: checkpointFailure.sourceSequence,
                        reason: checkpointFailure.reason
                    ))
                }
            } else {
                failures.append(recordFailure(
                    projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot,
                    sourceSequence: snapshotSourceSequence,
                    reason: describeError(error)
                ))
            }
        } catch {
            failures.append(recordFailure(
                projectionName: RuntimeHostDiagnosticProjectionNames.currentSnapshot,
                sourceSequence: snapshotSourceSequence,
                reason: describeError(error)
            ))
        }

        guard failures.isEmpty else {
            throw RuntimeHostDiagnosticsProjectionWorkflowError.projectionFailed(failures)
        }
        return RuntimeHostDiagnosticsProjectionResult(
            projectedEventCount: projectedEventCount,
            snapshotSourceSequence: snapshotSourceSequence
        )
    }

    private func recordFailure(
        projectionName: String,
        sourceSequence: Int,
        reason: String
    ) -> RuntimeHostDiagnosticsProjectionFailure {
        do {
            try repository.recordDiagnosticProjectionFailure(
                projectionName: projectionName,
                sourceSequence: sourceSequence,
                reason: reason,
                failedAt: timestamp()
            )
            return RuntimeHostDiagnosticsProjectionFailure(
                projectionName: projectionName,
                sourceSequence: sourceSequence,
                reason: reason,
                failureRecordingError: nil
            )
        } catch {
            return RuntimeHostDiagnosticsProjectionFailure(
                projectionName: projectionName,
                sourceSequence: sourceSequence,
                reason: reason,
                failureRecordingError: describeError(error)
            )
        }
    }
}
