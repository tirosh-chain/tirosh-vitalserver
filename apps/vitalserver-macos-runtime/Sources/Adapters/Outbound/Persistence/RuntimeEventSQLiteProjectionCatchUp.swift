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

    public func catchUpIfDue() {
        let currentTime = now()
        guard secondary.catchUpDue(now: currentTime, intervalSeconds: intervalSeconds) else {
            return
        }

        catchUp(at: currentTime)
    }

    public func catchUpNow() {
        catchUp(at: now())
    }

    private func catchUp(at currentTime: Date) {
        let readResult = primary.allResult()
        for issue in readResult.issues {
            log("runtime event jsonl read issue during sqlite catch-up issue=\(issue)")
        }

        do {
            try secondary.upsert(readResult.events)
            try secondary.markCaughtUp(at: currentTime)
        } catch {
            log("runtime event sqlite catch-up failed; rebuilding index error=\(error)")
            do {
                try secondary.rebuild(from: readResult.events)
                try secondary.markCaughtUp(at: currentTime)
            } catch {
                log("runtime event sqlite rebuild failed error=\(error)")
            }
        }
    }
}
