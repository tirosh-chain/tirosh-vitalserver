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

    public func loadEvents() async throws -> RuntimeEventHistory {
        client.loadRuntimeEvents(limit: RuntimeControlEventQuery.maximumLimit)
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
