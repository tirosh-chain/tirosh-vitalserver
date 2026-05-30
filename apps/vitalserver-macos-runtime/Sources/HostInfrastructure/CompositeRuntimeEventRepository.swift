import Contracts
import Core
import Foundation

public struct CompositeRuntimeEventRepository: RuntimeEventRepository, RuntimeEventHistoryReading {
    public static let defaultCatchUpIntervalSeconds: TimeInterval = 30

    private let primary: JSONLRuntimeEventRepository
    private let secondary: SQLiteRuntimeEventRepository
    private let catchUpIntervalSeconds: TimeInterval
    private let now: () -> Date
    private let log: (String) -> Void

    public init(
        primary: JSONLRuntimeEventRepository,
        secondary: SQLiteRuntimeEventRepository,
        catchUpIntervalSeconds: TimeInterval = Self.defaultCatchUpIntervalSeconds,
        now: @escaping () -> Date = Date.init,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.primary = primary
        self.secondary = secondary
        self.catchUpIntervalSeconds = catchUpIntervalSeconds
        self.now = now
        self.log = log
    }

    public func append(_ event: RuntimeEventDocument) throws {
        try primary.append(event)
        do {
            try secondary.append(event)
        } catch {
            log("runtime event sqlite append failed eventID=\(event.id) error=\(error)")
        }
    }

    public func recent(limit: Int) -> [RuntimeEventDocument] {
        query(RuntimeEventQuery(limit: limit)).events
    }

    public func query(_ query: RuntimeEventQuery) -> RuntimeEventPage {
        catchUpSecondaryIndexIfDue()
        return secondary.query(query)
    }

    private func catchUpSecondaryIndexIfDue() {
        let currentTime = now()
        guard secondary.catchUpDue(now: currentTime, intervalSeconds: catchUpIntervalSeconds) else {
            return
        }

        let primaryEvents = primary.all()
        do {
            try secondary.upsert(primaryEvents)
            try secondary.markCaughtUp(at: currentTime)
        } catch {
            log("runtime event sqlite catch-up failed; rebuilding index error=\(error)")
            do {
                try secondary.rebuild(from: primaryEvents)
                try secondary.markCaughtUp(at: currentTime)
            } catch {
                log("runtime event sqlite rebuild failed error=\(error)")
            }
        }
    }
}
