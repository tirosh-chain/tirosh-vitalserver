import Foundation
import Contracts
import RuntimeControl
import Errors

@MainActor
public final class MacTestKitController: RuntimeTestKitControlling, RuntimeTestKitVitalFileUploading {
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
        switch apiEndpointResolution(from: runtimeStatus) {
        case .available(let apiBaseURL):
            return await loadAvailableTestKitStatus(runtimeStatus: runtimeStatus, apiBaseURL: apiBaseURL)
        case .unavailable(let message):
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
    }

    private func loadAvailableTestKitStatus(runtimeStatus: RuntimeStatus, apiBaseURL: String) async -> RuntimeTestKitStatus {
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

    public func restartVirtualRecorders(sessionID: String?, bedroomName: String?) async throws -> RuntimeTestKitSession? {
        let apiBaseURL = try await requireAPIBaseURL()
        let selectedSessionID = try requireSessionID(sessionID)

        let session = try await apiService.restartSession(
            apiBaseURL: apiBaseURL,
            sessionID: selectedSessionID,
            bedroomName: bedroomName
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

    public func uploadVitalFiles(
        _ request: RuntimeTestKitVitalFileUploadRequest
    ) async throws -> RuntimeTestKitVitalFileUploadSummary {
        guard !request.filePaths.isEmpty else {
            throw RuntimeTestKitVitalFileUploadError.noFilesSelected
        }

        let bedRoomNames = try RuntimeTestKitVitalFileUploadPolicy.uniqueBedRoomNames(
            filePaths: request.filePaths
        )
        if request.registerBeds {
            _ = try await createTestKitBeds(RuntimeTestKitCreateBedsRequest(
                roomNames: bedRoomNames,
                prefix: "",
                appendRandomSuffix: false
            ))
        }

        var results: [RuntimeTestKitVitalFileUploadFileResult] = []
        for path in request.filePaths {
            let fileURL = URL(fileURLWithPath: path)
            let filename = fileURL.lastPathComponent
            guard let bedRoomName = RuntimeTestKitVitalFileUploadPolicy.bedRoomName(filename: filename) else {
                throw RuntimeTestKitVitalFileUploadError.invalidFilename(filename)
            }
            results.append(try await apiService.uploadVitalFile(
                fileURL: fileURL,
                bedRoomName: bedRoomName,
                vitalServerBaseURL: request.vitalServerBaseURL,
                endpoint: request.endpoint
            ))
        }

        return RuntimeTestKitVitalFileUploadSummary(
            files: results,
            bedRoomNames: bedRoomNames
        )
    }

    private func ensureAPIAvailable(apiBaseURL: String) async throws {
        let apiHealth = await testKitAPIHealth(apiBaseURL: apiBaseURL)
        guard apiHealth.isHealthy else {
            throw MacTestKitControllerError.apiUnavailable(apiBaseURL)
        }
    }

    private func requireAPIBaseURL() async throws -> String {
        switch await apiEndpointResolution() {
        case .available(let apiBaseURL):
            return apiBaseURL
        case .unavailable(let message):
            throw MacTestKitControllerError.apiEndpointUnavailable(message)
        }
    }

    private func apiEndpointResolution() async -> MacTestKitAPIEndpointResolution {
        let status = await statusProvider()
        return apiEndpointResolution(from: status)
    }

    private func apiEndpointResolution(from status: RuntimeStatus) -> MacTestKitAPIEndpointResolution {
        configuration.apiEndpoint.resolve(from: status)
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
