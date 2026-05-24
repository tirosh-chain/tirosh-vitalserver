import Contracts
import Core

public struct CompositeRuntimeEventRepository: RuntimeEventRepository {
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
        let secondaryEvents = secondary.recent(limit: limit)
        if !secondaryEvents.isEmpty {
            return secondaryEvents
        }

        let primaryEvents = primary.all()
        guard !primaryEvents.isEmpty else {
            return []
        }

        try? secondary.rebuild(from: primaryEvents)
        let rebuiltEvents = secondary.recent(limit: limit)
        if !rebuiltEvents.isEmpty {
            return rebuiltEvents
        }
        return Array(primaryEvents.suffix(limit))
    }
}
