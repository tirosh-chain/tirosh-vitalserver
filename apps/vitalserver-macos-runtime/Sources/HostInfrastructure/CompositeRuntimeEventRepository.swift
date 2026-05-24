import Contracts
import Core

public struct CompositeRuntimeEventRepository: RuntimeEventRepository {
    private let primary: any RuntimeEventRepository
    private let secondary: any RuntimeEventRepository

    public init(primary: any RuntimeEventRepository, secondary: any RuntimeEventRepository) {
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
        return primary.recent(limit: limit)
    }
}
