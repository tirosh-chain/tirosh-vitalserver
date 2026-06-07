import Foundation
import Contracts
import RuntimeControl
import Errors

@MainActor
public final class MacTestKitController: RuntimeTestKitControlling {
    private let configuration: MacTestKitControllerConfiguration
    private let statusProvider: () async -> RuntimeStatus
    private let apiService: MacTestKitAPIService

    public init(
        configuration: MacTestKitControllerConfiguration = MacTestKitControllerConfiguration(),
        httpClient: any MacTestKitHTTPClient = URLSessionMacTestKitHTTPClient(),
        apiHealthCheck: (@Sendable (String) async -> Bool)? = nil
    ) {
        let statusReader = SystemRuntimeStatusReader(paths: RuntimePaths())
        let apiClient = MacTestKitAPIClient(
            httpClient: httpClient,
            healthRead: Self.healthRead(apiHealthCheck)
        )
        self.configuration = configuration
        self.apiService = MacTestKitAPIService(configuration: configuration, apiClient: apiClient)
        self.statusProvider = {
            statusReader.loadStatus(settings: RuntimeSettings())
        }
    }

    public init(
        configuration: MacTestKitControllerConfiguration = MacTestKitControllerConfiguration(),
        statusProvider: @escaping () async -> RuntimeStatus,
        httpClient: any MacTestKitHTTPClient = URLSessionMacTestKitHTTPClient(),
        apiHealthCheck: (@Sendable (String) async -> Bool)? = nil
    ) {
        let apiClient = MacTestKitAPIClient(
            httpClient: httpClient,
            healthRead: Self.healthRead(apiHealthCheck)
        )
        self.configuration = configuration
        self.statusProvider = statusProvider
        self.apiService = MacTestKitAPIService(configuration: configuration, apiClient: apiClient)
    }

    init(
        configuration: MacTestKitControllerConfiguration = MacTestKitControllerConfiguration(),
        statusProvider: @escaping () async -> RuntimeStatus,
        httpClient: any MacTestKitHTTPClient = URLSessionMacTestKitHTTPClient(),
        apiHealthRead: @escaping @Sendable (String) async -> MacTestKitAPIHealthRead
    ) {
        let apiClient = MacTestKitAPIClient(httpClient: httpClient, healthRead: apiHealthRead)
        self.configuration = configuration
        self.statusProvider = statusProvider
        self.apiService = MacTestKitAPIService(configuration: configuration, apiClient: apiClient)
    }

    public func loadTestKitStatus() async -> RuntimeTestKitStatus {
        guard configuration.enabled else {
            return RuntimeTestKitStatus(enabled: false, state: .disabled)
        }

        let runtimeStatus = await statusProvider()
        guard let apiBaseURL = apiBaseURL(from: runtimeStatus) else {
            let message = configuration.apiEndpoint.unavailableDescription
            return RuntimeTestKitStatus(
                enabled: true,
                state: .failed,
                serviceName: configuration.serviceName,
                recorderTargetURL: configuration.recorderTargetURL,
                lastError: message,
                readIssues: [
                    RuntimeTestKitReadIssue(source: "apiEndpoint", message: message),
                ]
            )
        }

        let apiHealth = await testKitAPIHealth(apiBaseURL: apiBaseURL)
        guard apiHealth.isHealthy else {
            let service = RuntimeTestKitAvailabilityPolicy.service(
                in: runtimeStatus,
                serviceName: configuration.serviceName
            )
            let message = RuntimeTestKitAvailabilityPolicy.unavailableMessage(
                for: service,
                serviceName: configuration.serviceName,
                apiBaseURL: apiBaseURL,
                healthIssue: apiHealth.issue
            )
            return RuntimeTestKitStatus(
                enabled: true,
                state: RuntimeTestKitAvailabilityPolicy.unavailableState(for: service),
                serviceName: configuration.serviceName,
                apiBaseURL: apiBaseURL,
                recorderTargetURL: configuration.recorderTargetURL,
                lastError: message,
                readIssues: RuntimeTestKitAvailabilityPolicy.unavailableReadIssues(
                    for: service,
                    serviceName: configuration.serviceName,
                    message: message,
                    healthIssue: apiHealth.issue
                )
            )
        }

        let sessions: [RuntimeTestKitSession]
        let beds: [RuntimeTestKitBed]
        do {
            sessions = try await apiService.loadSessions(apiBaseURL: apiBaseURL)
            beds = try await apiService.loadBeds(apiBaseURL: apiBaseURL)
        } catch {
            let message = "TestKit container API read failed: \(error.localizedDescription)"
            return RuntimeTestKitStatus(
                enabled: true,
                state: .failed,
                serviceName: configuration.serviceName,
                apiBaseURL: apiBaseURL,
                recorderTargetURL: configuration.recorderTargetURL,
                lastError: message,
                readIssues: [
                    RuntimeTestKitReadIssue(source: "containerAPI", message: message),
                ]
            )
        }
        let activeSession = RuntimeTestKitSessionStatePolicy.preferredActiveSession(from: sessions)

        return RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            serviceName: configuration.serviceName,
            apiBaseURL: apiBaseURL,
            recorderTargetURL: configuration.recorderTargetURL,
            activeSession: activeSession,
            sessions: sessions,
            beds: beds
        )
    }

    public func createTestKitBeds(_ request: RuntimeTestKitCreateBedsRequest) async throws -> [RuntimeTestKitBed] {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        let beds = try await apiService.createBeds(request, apiBaseURL: apiBaseURL)
        return beds
    }

    public func deleteTestKitBeds(_ request: RuntimeTestKitDeleteBedsRequest) async throws -> [RuntimeTestKitBed] {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        let beds = try await apiService.deleteBeds(request, apiBaseURL: apiBaseURL)
        return beds
    }

    public func resetTestKitBeds() async throws -> [RuntimeTestKitBed] {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        let beds = try await apiService.resetBeds(apiBaseURL: apiBaseURL)
        return beds
    }

    public func startVirtualRecorders(_ request: RuntimeTestKitVirtualRecorderStartRequest) async throws -> RuntimeTestKitSession {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        let session = try await apiService.startSession(request, apiBaseURL: apiBaseURL)

        return session
    }

    public func stopVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        try await sessionAction(sessionID: sessionID, pathComponent: "stop")
    }

    public func pauseVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        try await sessionAction(sessionID: sessionID, pathComponent: "pause")
    }

    public func resumeVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        try await sessionAction(sessionID: sessionID, pathComponent: "resume")
    }

    public func restartVirtualRecorders(sessionID: String?, bedRoomNames: [String]) async throws -> RuntimeTestKitSession? {
        let apiBaseURL = try await requireAPIBaseURL()
        let selectedSessionID = try requireSessionID(sessionID)

        let session = try await apiService.restartSession(
            apiBaseURL: apiBaseURL,
            sessionID: selectedSessionID,
            bedRoomNames: bedRoomNames
        )

        return session
    }

    public func deleteVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        let apiBaseURL = try await requireAPIBaseURL()
        let selectedSessionID = try requireSessionID(sessionID)

        let session = try await apiService.deleteSession(apiBaseURL: apiBaseURL, sessionID: selectedSessionID)

        return session
    }

    public func deleteVirtualRecorder(vrcode: String) async throws -> RuntimeTestKitRecorderDeletion {
        let apiBaseURL = try await requireAPIBaseURL()
        return try await apiService.deleteRecorder(apiBaseURL: apiBaseURL, vrcode: vrcode)
    }

    public func resetVirtualRecorders() async throws -> RuntimeTestKitStatus {
        let apiBaseURL = try await requireAPIBaseURL()

        try await apiService.resetSessions(apiBaseURL: apiBaseURL)

        return await loadTestKitStatus()
    }

    private func ensureAPIAvailable(apiBaseURL: String) async throws {
        let apiHealth = await testKitAPIHealth(apiBaseURL: apiBaseURL)
        guard apiHealth.isHealthy else {
            throw MacTestKitControllerError.apiUnavailable(apiBaseURL)
        }
    }

    private func requireAPIBaseURL() async throws -> String {
        guard let apiBaseURL = await apiBaseURL() else {
            throw MacTestKitControllerError.apiEndpointUnavailable(configuration.apiEndpoint.unavailableDescription)
        }
        return apiBaseURL
    }

    private func apiBaseURL() async -> String? {
        let status = await statusProvider()
        return apiBaseURL(from: status)
    }

    private func apiBaseURL(from status: RuntimeStatus) -> String? {
        configuration.apiEndpoint.baseURL(from: status)
    }

    private func sessionAction(
        sessionID: String?,
        pathComponent: String
    ) async throws -> RuntimeTestKitSession? {
        let apiBaseURL = try await requireAPIBaseURL()
        let selectedSessionID = try requireSessionID(sessionID)

        let session = try await apiService.sessionAction(
            apiBaseURL: apiBaseURL,
            sessionID: selectedSessionID,
            pathComponent: pathComponent
        )

        return session
    }

    private func requireSessionID(_ value: String?) throws -> String {
        guard let sessionID = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionID.isEmpty
        else {
            throw MacTestKitControllerError.missingSessionID
        }
        return sessionID
    }

    private func testKitAPIHealth(apiBaseURL: String) async -> MacTestKitAPIHealthRead {
        await apiService.health(apiBaseURL: apiBaseURL)
    }

    private static func healthRead(
        _ apiHealthCheck: (@Sendable (String) async -> Bool)?
    ) -> (@Sendable (String) async -> MacTestKitAPIHealthRead)? {
        guard let apiHealthCheck else {
            return nil
        }
        return { apiBaseURL in
            await apiHealthCheck(apiBaseURL) ? .healthy : .unreachable(nil)
        }
    }
}
