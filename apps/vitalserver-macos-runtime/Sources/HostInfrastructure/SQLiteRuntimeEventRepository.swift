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

    public func recent(limit: Int) -> [RuntimeEventDocument] {
        store.recent(limit: limit)
    }

    public func rebuild(from events: [RuntimeEventDocument]) throws {
        try store.rebuild(from: events)
    }
}
