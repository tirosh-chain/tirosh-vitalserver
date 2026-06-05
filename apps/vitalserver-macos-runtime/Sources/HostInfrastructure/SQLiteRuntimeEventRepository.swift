import Contracts
import Core
import Foundation

public struct SQLiteRuntimeEventRepository: RuntimeEventRepository {
    private let store: SQLiteRuntimeObservabilityStore

    public init(url: URL) {
        self.store = SQLiteRuntimeObservabilityStore(url: url)
    }

    public init(store: SQLiteRuntimeObservabilityStore) {
        self.store = store
    }

    public func append(_ event: RuntimeEventDocument) throws {
        try store.append(event)
    }

    public func query(_ query: RuntimeEventQuery) -> RuntimeEventPage {
        store.query(query)
    }

    public func upsert(_ events: [RuntimeEventDocument]) throws {
        try store.upsertRuntimeEvents(events)
    }

    public func rebuild(from events: [RuntimeEventDocument]) throws {
        try store.rebuild(from: events)
    }

    public func catchUpDue(now: Date, intervalSeconds: TimeInterval) -> Bool {
        store.runtimeEventIndexCatchUpDue(now: now, intervalSeconds: intervalSeconds)
    }

    public func markCaughtUp(at date: Date) throws {
        try store.markRuntimeEventIndexCaughtUp(at: date)
    }
}
