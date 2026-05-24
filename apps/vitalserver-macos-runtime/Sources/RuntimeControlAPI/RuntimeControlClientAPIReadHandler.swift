import RuntimeControl

@MainActor
public struct RuntimeControlClientAPIReadHandler: RuntimeControlAPIReadHandler {
    private let client: any RuntimeControlClient

    public init(client: any RuntimeControlClient) {
        self.client = client
    }

    public func loadCapabilities() async throws -> RuntimeControlCapabilities {
        client.capabilities
    }

    public func loadStatus() async throws -> RuntimeStatus {
        let settings = client.loadSettings()
        return client.loadStatus(settings: settings)
    }

    public func loadEvents(query: RuntimeControlEventQuery) async throws -> RuntimeEventHistory {
        let scanLimit = query.eventType == nil && query.since == nil
            ? query.limit
            : RuntimeControlEventQuery.maximumLimit
        let history = client.loadRuntimeEvents(limit: scanLimit)
        let filtered = history.events
            .filter { event in
                guard let eventType = query.eventType else {
                    return true
                }
                return event.eventType.rawValue == eventType
            }
            .filter { event in
                guard let since = query.since else {
                    return true
                }
                return event.timestamp >= since
            }
            .suffix(query.limit)
        return RuntimeEventHistory(events: Array(filtered))
    }

    public func loadHealthStatus() async throws -> RuntimeStatus {
        let settings = client.loadSettings()
        return await client.loadHealthStatus(settings: settings)
    }

    public func loadSettings() async throws -> RuntimeSettings {
        client.loadSettings()
    }

    public func loadReleaseInfo() async throws -> RuntimeReleaseInfo {
        try await client.loadReleaseInfo()
    }

    public func loadInstallInfo() async throws -> RuntimeInstallInfo {
        client.loadInstallInfo()
    }
}
