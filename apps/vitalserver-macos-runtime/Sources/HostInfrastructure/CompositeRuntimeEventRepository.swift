import Contracts
import Core

public struct CompositeRuntimeEventRepository: RuntimeEventRepository, RuntimeEventHistoryReading {
    private let primary: JSONLRuntimeEventRepository
    private let secondary: SQLiteRuntimeEventRepository

    public init(primary: JSONLRuntimeEventRepository, secondary: SQLiteRuntimeEventRepository) {
        self.primary = primary
        self.secondary = secondary
    }

    public func append(_ event: RuntimeEventDocument) throws {
        try primary.append(event)
        try? secondary.append(event)
    }

    public func recent(limit: Int) -> [RuntimeEventDocument] {
        query(RuntimeEventQuery(limit: limit)).events
    }

    public func query(_ query: RuntimeEventQuery) -> RuntimeEventPage {
        let secondaryPage = secondary.query(query)
        if !secondaryPage.events.isEmpty {
            return secondaryPage
        }

        let primaryEvents = primary.all()
        guard !primaryEvents.isEmpty else {
            return RuntimeEventPage(events: [])
        }

        try? secondary.rebuild(from: primaryEvents)
        let rebuiltPage = secondary.query(query)
        if !rebuiltPage.events.isEmpty {
            return rebuiltPage
        }
        return primary.query(query)
    }
}
