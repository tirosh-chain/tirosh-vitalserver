import Contracts
import Core
import Foundation

public struct CompositeRuntimeEventRepository: RuntimeEventRepository, RuntimeEventHistoryReading {
    public static let defaultCatchUpIntervalSeconds: TimeInterval = 30

    private let primary: JSONLRuntimeEventRepository
    private let secondary: SQLiteRuntimeEventRepository
    private let catchUpIntervalSeconds: TimeInterval
    private let now: () -> Date

    public init(
        primary: JSONLRuntimeEventRepository,
        secondary: SQLiteRuntimeEventRepository,
        catchUpIntervalSeconds: TimeInterval = Self.defaultCatchUpIntervalSeconds,
        now: @escaping () -> Date = Date.init
    ) {
        self.primary = primary
        self.secondary = secondary
        self.catchUpIntervalSeconds = catchUpIntervalSeconds
        self.now = now
    }

    public func append(_ event: RuntimeEventDocument) throws {
        try primary.append(event)
        try? secondary.append(event)
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
            do {
                try secondary.rebuild(from: primaryEvents)
                try secondary.markCaughtUp(at: currentTime)
            } catch {
                return
            }
        }
    }
}
