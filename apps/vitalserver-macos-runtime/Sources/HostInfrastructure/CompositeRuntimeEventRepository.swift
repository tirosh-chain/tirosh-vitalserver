import Contracts
import Core
import Foundation

public struct CompositeRuntimeEventRepository: RuntimeEventRepository, RuntimeEventHistoryReading {
    private let primary: JSONLRuntimeEventRepository
    private let secondary: SQLiteRuntimeEventRepository
    private let log: (String) -> Void

    public init(
        primary: JSONLRuntimeEventRepository,
        secondary: SQLiteRuntimeEventRepository,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.primary = primary
        self.secondary = secondary
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
        let secondaryPage = secondary.query(query)
        guard let secondaryReadError = secondaryPage.readError else {
            return secondaryPage
        }
        let primaryPage = primary.query(query)
        if !primaryPage.events.isEmpty {
            log("runtime event sqlite query unavailable; served events from jsonl primary error=\(secondaryReadError)")
        }
        return RuntimeEventPage(
            events: primaryPage.events,
            nextCursor: primaryPage.nextCursor,
            matchingCount: primaryPage.matchingCount,
            readError: [secondaryReadError, primaryPage.readError]
                .compactMap { $0 }
                .joined(separator: "; ")
        )
    }
}
