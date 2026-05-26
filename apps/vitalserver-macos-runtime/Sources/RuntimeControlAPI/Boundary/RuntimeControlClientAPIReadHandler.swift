import Foundation
import RuntimeControl
import Core
import Contracts

@MainActor
public struct RuntimeControlClientAPIReadHandler: RuntimeControlAPIReadHandler {
    private let client: any RuntimeControlClient
    private let hostClient: (any RuntimeHostClient)?

    public init(client: any RuntimeControlClient, hostClient: (any RuntimeHostClient)? = nil) {
        self.client = client
        self.hostClient = hostClient
    }

    public func loadCapabilities() async throws -> RuntimeControlCapabilities {
        client.capabilities
    }

    public func loadStatus() async throws -> RuntimeStatus {
        let settings = client.loadSettings()
        return client.loadStatus(settings: settings)
    }

    public func loadEvents(query: RuntimeEventQuery) async throws -> RuntimeEventHistory {
        client.loadRuntimeEvents(query: query)
    }

    public func loadVitalDBObservation() async throws -> VitalDBObservationDocument? {
        client.loadVitalDBObservation()
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

    public func loadLogText(request: RuntimeLogTextRequest) async throws -> RuntimeLogTextResponse {
        guard let hostClient else {
            throw RuntimeControlAPIReadHandlerError.hostAffordanceUnavailable
        }
        return RuntimeLogTextResponse(
            text: await hostClient.loadLogText(
                sourceID: request.source,
                helperMessage: request.helperMessage,
                lineLimit: request.lineLimit
            )
        )
    }
}

public enum RuntimeControlAPIReadHandlerError: LocalizedError, Equatable {
    case hostAffordanceUnavailable

    public var errorDescription: String? {
        switch self {
        case .hostAffordanceUnavailable:
            return "Host affordance client is unavailable."
        }
    }
}
