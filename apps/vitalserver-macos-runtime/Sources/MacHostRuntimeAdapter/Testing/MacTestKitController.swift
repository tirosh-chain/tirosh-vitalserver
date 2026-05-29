import Foundation
import Contracts
import RuntimeControl

@MainActor
public final class MacTestKitController: RuntimeTestKitControlling {
    private let configuration: MacTestKitControllerConfiguration
    private let statusProvider: () async -> RuntimeStatus
    private var activeSessionID: String?
    private var lastError: String?
    private let requestTimeout: TimeInterval = 5

    public init(configuration: MacTestKitControllerConfiguration = MacTestKitControllerConfiguration()) {
        let statusReader = SystemRuntimeStatusReader(paths: RuntimePaths())
        self.configuration = configuration
        self.statusProvider = {
            statusReader.loadStatus(settings: RuntimeSettings())
        }
    }

    public init(
        configuration: MacTestKitControllerConfiguration = MacTestKitControllerConfiguration(),
        statusProvider: @escaping () async -> RuntimeStatus
    ) {
        self.configuration = configuration
        self.statusProvider = statusProvider
    }

    public func loadTestKitStatus() async -> RuntimeTestKitStatus {
        guard configuration.enabled else {
            return RuntimeTestKitStatus(enabled: false, state: .disabled)
        }

        let runtimeStatus = await statusProvider()
        guard let apiBaseURL = apiBaseURL(from: runtimeStatus) else {
            return RuntimeTestKitStatus(
                enabled: true,
                state: .failed,
                serviceName: configuration.serviceName,
                recorderTargetURL: configuration.recorderTargetURL,
                lastError: MacTestKitControllerError.missingVMIP.localizedDescription
            )
        }

        let healthy = await testKitAPIIsHealthy(apiBaseURL: apiBaseURL)
        guard healthy else {
            let service = testKitService(in: runtimeStatus)
            return RuntimeTestKitStatus(
                enabled: true,
                state: unavailableState(for: service),
                serviceName: configuration.serviceName,
                apiBaseURL: apiBaseURL,
                recorderTargetURL: configuration.recorderTargetURL,
                lastError: lastError ?? unavailableMessage(for: service, apiBaseURL: apiBaseURL)
            )
        }

        let sessions: [RuntimeTestKitSession]
        let beds: [RuntimeTestKitBed]
        do {
            sessions = try await loadSessions(apiBaseURL: apiBaseURL)
            beds = try await loadBeds(apiBaseURL: apiBaseURL)
        } catch {
            let message = "TestKit container API read failed: \(error.localizedDescription)"
            lastError = message
            return RuntimeTestKitStatus(
                enabled: true,
                state: .failed,
                serviceName: configuration.serviceName,
                apiBaseURL: apiBaseURL,
                recorderTargetURL: configuration.recorderTargetURL,
                lastError: message
            )
        }
        lastError = nil
        let activeSession = preferredActiveSession(from: sessions)

        return RuntimeTestKitStatus(
            enabled: true,
            state: .running,
            serviceName: configuration.serviceName,
            apiBaseURL: apiBaseURL,
            recorderTargetURL: configuration.recorderTargetURL,
            activeSession: activeSession,
            sessions: sessions,
            beds: beds,
            lastError: lastError
        )
    }

    public func createTestKitBeds(_ request: RuntimeTestKitCreateBedsRequest) async throws -> [RuntimeTestKitBed] {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/beds")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let response = try await decode(TestKitBedsResponse.self, from: urlRequest)
        lastError = nil
        return response.beds
    }

    public func deleteTestKitBeds(_ request: RuntimeTestKitDeleteBedsRequest) async throws -> [RuntimeTestKitBed] {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        let requestBody = TestKitDeleteBedsRequest(
            targetURL: configuration.recorderTargetURL,
            roomNames: request.roomNames
        )
        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/beds/delete")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let response = try await decode(TestKitBedsResponse.self, from: urlRequest)
        lastError = nil
        return response.beds
    }

    public func resetTestKitBeds() async throws -> [RuntimeTestKitBed] {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        var urlRequest = apiRequest(
            apiBaseURL: apiBaseURL,
            path: "/beds",
            queryItems: [
                URLQueryItem(name: "targetUrl", value: configuration.recorderTargetURL)
            ]
        )
        urlRequest.httpMethod = "DELETE"

        let response = try await decode(TestKitBedsResponse.self, from: urlRequest)
        lastError = nil
        return response.beds
    }

    public func startVirtualRecorders(_ request: RuntimeTestKitVirtualRecorderStartRequest) async throws -> RuntimeTestKitSession {
        let apiBaseURL = try await requireAPIBaseURL()
        try await ensureAPIAvailable(apiBaseURL: apiBaseURL)

        let requestBody = TestKitStartSessionRequest(
            runtimeRequest: request,
            targetURL: configuration.recorderTargetURL
        )
        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/sessions")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let session = try await decode(RuntimeTestKitSession.self, from: urlRequest)
        activeSessionID = session.id
        lastError = nil

        return session
    }

    public func stopVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        try await sessionAction(sessionID: sessionID, pathComponent: "stop", clearActiveSession: true)
    }

    public func pauseVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        try await sessionAction(sessionID: sessionID, pathComponent: "pause")
    }

    public func resumeVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        try await sessionAction(sessionID: sessionID, pathComponent: "resume")
    }

    public func restartVirtualRecorders(sessionID: String?, bedRoomNames: [String]) async throws -> RuntimeTestKitSession? {
        let apiBaseURL = try await requireAPIBaseURL()
        let selectedSessionID = sessionID ?? activeSessionID
        guard let selectedSessionID else {
            return nil
        }

        let requestBody = TestKitRestartSessionRequest(bedRoomNames: bedRoomNames)
        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/sessions/\(selectedSessionID)/restart")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let session = try await decode(RuntimeTestKitSession.self, from: urlRequest)
        activeSessionID = session.id
        lastError = nil

        return session
    }

    public func deleteVirtualRecorders(sessionID: String?) async throws -> RuntimeTestKitSession? {
        let apiBaseURL = try await requireAPIBaseURL()
        let selectedSessionID = sessionID ?? activeSessionID
        guard let selectedSessionID else {
            return nil
        }

        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/sessions/\(selectedSessionID)")
        urlRequest.httpMethod = "DELETE"

        let session = try await decode(RuntimeTestKitSession.self, from: urlRequest)
        if activeSessionID == selectedSessionID {
            activeSessionID = nil
        }
        lastError = nil

        return session
    }

    public func deleteVirtualRecorder(vrcode: String) async throws -> RuntimeTestKitRecorderDeletion {
        let apiBaseURL = try await requireAPIBaseURL()
        let requestBody = TestKitDeleteRecorderRequest(
            targetURL: configuration.recorderTargetURL,
            vrcode: vrcode
        )
        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/recorders/delete")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let deletion = try await decode(RuntimeTestKitRecorderDeletion.self, from: urlRequest)
        lastError = deletion.error
        return deletion
    }

    public func resetVirtualRecorders() async throws -> RuntimeTestKitStatus {
        let apiBaseURL = try await requireAPIBaseURL()

        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/sessions")
        urlRequest.httpMethod = "DELETE"
        _ = try await decode(TestKitSessionsResponse.self, from: urlRequest)

        activeSessionID = nil
        lastError = nil

        return await loadTestKitStatus()
    }

    private func ensureAPIAvailable(apiBaseURL: String) async throws {
        guard await testKitAPIIsHealthy(apiBaseURL: apiBaseURL) else {
            lastError = "TestKit container API is not reachable at \(apiBaseURL)."
            throw MacTestKitControllerError.apiUnavailable(apiBaseURL)
        }
    }

    private func requireAPIBaseURL() async throws -> String {
        guard let apiBaseURL = await apiBaseURL() else {
            lastError = MacTestKitControllerError.missingVMIP.localizedDescription
            throw MacTestKitControllerError.missingVMIP
        }
        return apiBaseURL
    }

    private func apiBaseURL() async -> String? {
        let status = await statusProvider()
        return apiBaseURL(from: status)
    }

    private func apiBaseURL(from status: RuntimeStatus) -> String? {
        guard let vmIP = status.vmIP, !vmIP.isEmpty else {
            return nil
        }
        return "http://\(vmIP):\(configuration.hostPort)"
    }

    private func testKitService(in status: RuntimeStatus) -> RuntimeContainerServiceObservation? {
        status.containerObservation?.composeServices.first { $0.service == configuration.serviceName }
    }

    private func unavailableState(for service: RuntimeContainerServiceObservation?) -> RuntimeTestKitState {
        guard let service else {
            return .stopped
        }

        switch service.state?.lowercased() {
        case "running", "restarting", "created":
            return .starting
        case "exited", "dead":
            return .failed
        default:
            return .stopped
        }
    }

    private func unavailableMessage(
        for service: RuntimeContainerServiceObservation?,
        apiBaseURL: String
    ) -> String {
        guard let service else {
            return "TestKit container is not running. TestKit is optional and does not affect VitalServer."
        }

        let state = service.state ?? "not reported"
        let health = service.health ?? "not reported"
        return "TestKit container API is not reachable at \(apiBaseURL). Container state: \(state), health: \(health)."
    }

    private func loadSessions(apiBaseURL: String) async throws -> [RuntimeTestKitSession] {
        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/sessions")
        urlRequest.httpMethod = "GET"
        let response = try await decode(TestKitSessionsResponse.self, from: urlRequest)
        return response.sessions
    }

    private func loadBeds(apiBaseURL: String) async throws -> [RuntimeTestKitBed] {
        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/beds")
        urlRequest.httpMethod = "GET"
        let response = try await decode(TestKitBedsResponse.self, from: urlRequest)
        return response.beds
    }

    private func preferredActiveSession(from sessions: [RuntimeTestKitSession]) -> RuntimeTestKitSession? {
        if let activeSessionID,
           let activeSession = sessions.first(where: { $0.id == activeSessionID }) {
            return activeSession
        }
        return sessions.first { ["running", "paused", "starting", "stopping"].contains($0.state) }
    }

    private func sessionAction(
        sessionID: String?,
        pathComponent: String,
        clearActiveSession: Bool = false
    ) async throws -> RuntimeTestKitSession? {
        let apiBaseURL = try await requireAPIBaseURL()
        let selectedSessionID = sessionID ?? activeSessionID
        guard let selectedSessionID else {
            return nil
        }

        var urlRequest = apiRequest(apiBaseURL: apiBaseURL, path: "/sessions/\(selectedSessionID)/\(pathComponent)")
        urlRequest.httpMethod = "POST"

        let session = try await decode(RuntimeTestKitSession.self, from: urlRequest)
        if clearActiveSession, activeSessionID == selectedSessionID {
            activeSessionID = nil
        } else {
            activeSessionID = selectedSessionID
        }
        lastError = nil

        return session
    }

    private func testKitAPIIsHealthy(apiBaseURL: String) async -> Bool {
        do {
            var request = apiRequest(apiBaseURL: apiBaseURL, path: "/health")
            request.httpMethod = "GET"
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacTestKitControllerError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw MacTestKitControllerError.requestFailed(message)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func apiURL(
        apiBaseURL: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL {
        var components = URLComponents(string: "\(apiBaseURL)\(path)")!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    private func apiRequest(
        apiBaseURL: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        URLRequest(
            url: apiURL(apiBaseURL: apiBaseURL, path: path, queryItems: queryItems),
            timeoutInterval: requestTimeout
        )
    }
}

public struct MacTestKitControllerConfiguration: Equatable, Sendable {
    public let enabled: Bool
    public let serviceName: String
    public let hostPort: Int
    public let recorderTargetURL: String

    public init(
        enabled: Bool = false,
        serviceName: String = "testkit",
        hostPort: Int = 18322,
        recorderTargetURL: String = "http://edge/"
    ) {
        self.enabled = enabled
        self.serviceName = serviceName
        self.hostPort = hostPort
        self.recorderTargetURL = recorderTargetURL
    }
}

private struct TestKitSessionsResponse: Decodable {
    let sessions: [RuntimeTestKitSession]
}

private struct TestKitBedsResponse: Decodable {
    let beds: [RuntimeTestKitBed]
}

private struct TestKitStartSessionRequest: Encodable {
    let targetURL: String
    let recorders: Int
    let bedRoomNames: [String]
    let vrcode: String?
    let version: String
    let intervalSeconds: Double
    let durationSeconds: Double?
    let maxMessages: Int?
    let shiftTime: Bool
    let generateFrames: Bool
    let scenario: String
    let defaultScenario: String

    init(
        runtimeRequest: RuntimeTestKitVirtualRecorderStartRequest,
        targetURL: String
    ) {
        self.targetURL = targetURL
        recorders = runtimeRequest.recorders
        bedRoomNames = runtimeRequest.bedRoomNames
        vrcode = runtimeRequest.vrcode
        version = runtimeRequest.version
        intervalSeconds = runtimeRequest.intervalSeconds
        durationSeconds = runtimeRequest.durationSeconds
        maxMessages = runtimeRequest.maxMessages
        shiftTime = runtimeRequest.shiftTime
        generateFrames = runtimeRequest.generateFrames
        scenario = runtimeRequest.scenario.rawValue
        defaultScenario = runtimeRequest.signalProfile.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case recorders
        case bedRoomNames
        case vrcode
        case version
        case intervalSeconds
        case durationSeconds
        case maxMessages
        case shiftTime
        case generateFrames
        case scenario
        case defaultScenario
    }
}

private struct TestKitDeleteRecorderRequest: Encodable {
    let targetURL: String
    let vrcode: String

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case vrcode
    }
}

private struct TestKitDeleteBedsRequest: Encodable {
    let targetURL: String
    let roomNames: [String]

    enum CodingKeys: String, CodingKey {
        case targetURL = "targetUrl"
        case roomNames
    }
}

private struct TestKitRestartSessionRequest: Encodable {
    let bedRoomNames: [String]
}

private enum MacTestKitControllerError: LocalizedError, Equatable {
    case missingVMIP
    case apiUnavailable(String)
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVMIP:
            return "TestKit container API is unavailable because the VM IP is not known yet."
        case .apiUnavailable(let apiBaseURL):
            return "TestKit container API is not reachable at \(apiBaseURL)."
        case .invalidResponse:
            return "TestKit API returned an invalid response."
        case .requestFailed(let message):
            return message
        }
    }
}
