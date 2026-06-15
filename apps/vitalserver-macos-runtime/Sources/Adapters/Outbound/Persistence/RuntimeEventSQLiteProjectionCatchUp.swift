import Contracts
import Foundation
import Errors

public struct RuntimeEventSQLiteProjectionCatchUp {
    public static let defaultIntervalSeconds: TimeInterval = 30

    private let primary: JSONLRuntimeEventRepository
    private let secondary: SQLiteRuntimeEventRepository
    private let intervalSeconds: TimeInterval
    private let now: () -> Date
    private let log: (String) -> Void

    public init(
        primary: JSONLRuntimeEventRepository,
        secondary: SQLiteRuntimeEventRepository,
        intervalSeconds: TimeInterval = Self.defaultIntervalSeconds,
        now: @escaping () -> Date = Date.init,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.primary = primary
        self.secondary = secondary
        self.intervalSeconds = intervalSeconds
        self.now = now
        self.log = log
    }

    @discardableResult
    public func catchUpIfDue() -> RuntimeEventSQLiteProjectionCatchUpResult {
        let currentTime = now()
        switch secondary.catchUpDue(now: currentTime, intervalSeconds: intervalSeconds) {
        case .due:
            break
        case .dueAfterReadFailure(let reason):
            log("runtime event sqlite catch-up due read failed; attempting catch-up reason=\(reason)")
        case .notDue:
            return .notDue
        }

        return catchUp(at: currentTime)
    }

    @discardableResult
    public func catchUpNow() -> RuntimeEventSQLiteProjectionCatchUpResult {
        catchUp(at: now())
    }

    private func catchUp(at currentTime: Date) -> RuntimeEventSQLiteProjectionCatchUpResult {
        let readResult = primary.allResult()
        for issue in readResult.issues {
            log("runtime event jsonl read issue during sqlite catch-up issue=\(issue)")
        }
        guard readResult.issues.isEmpty else {
            return .skippedDueToPrimaryReadIssues(readResult.issues)
        }

        do {
            try secondary.upsert(readResult.events)
            try secondary.markCaughtUp(at: currentTime)
            return .caughtUp(eventCount: readResult.events.count)
        } catch {
            log("runtime event sqlite catch-up failed; rebuilding index error=\(error)")
            do {
                try secondary.rebuild(from: readResult.events)
                try secondary.markCaughtUp(at: currentTime)
                return .rebuiltAfterSecondaryFailure(eventCount: readResult.events.count)
            } catch {
                log("runtime event sqlite rebuild failed error=\(error)")
                return .failed(String(describing: error))
            }
        }
    }
}

public enum RuntimeEventSQLiteProjectionCatchUpResult: Equatable, Sendable {
    case notDue
    case caughtUp(eventCount: Int)
    case rebuiltAfterSecondaryFailure(eventCount: Int)
    case skippedDueToPrimaryReadIssues([JSONLRuntimeEventReadIssue])
    case failed(String)
}
