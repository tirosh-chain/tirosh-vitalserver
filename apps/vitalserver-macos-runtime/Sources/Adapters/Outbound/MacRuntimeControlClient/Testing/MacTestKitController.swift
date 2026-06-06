import Foundation
import Contracts
import RuntimeControl
import Errors

@MainActor
public final class MacTestKitController: RuntimeTestKitControlling {
    private let configuration: MacTestKitControllerConfiguration
    private let statusProvider: () async -> RuntimeStatus
    private let apiHealthCheck: (String) async -> Bool
    private var activeSessionID: String?
    private var lastError: String?
    private let requestTimeout: TimeInterval = 5

    public init(
        configuration: MacTestKitControllerConfiguration = MacTestKitControllerConfiguration(),
        apiHealthCheck: ((String) async -> Bool)? = nil
    ) {
        let statusReader = SystemRuntimeStatusReader(paths: RuntimePaths())
        self.configuration = configuration
        self.apiHealthCheck = apiHealthCheck ?? Self.defaultAPIHealthCheck
        self.statusProvider = {
            statusReader.loadStatus(settings: RuntimeSettings())
        }
    }

    public init(
        configuration: MacTestKitControllerConfiguration = MacTestKitControllerConfiguration(),
        statusProvider: @escaping () async -> RuntimeStatus,
        apiHealthCheck: ((String) async -> Bool)? = nil
    ) {
        self.configuration = configuration
        self.statusProvider = statusProvider
        self.apiHealthCheck = apiHealthCheck ?? Self.defaultAPIHealthCheck
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

        let healthy = await testKitAPIIsHealthy(apiBaseURL: apiBaseURL)
        guard healthy else {
            let service = testKitService(in: runtimeStatus)
            let message = unavailableMessage(for: service, apiBaseURL: apiBaseURL)
            lastError = message
            return RuntimeTestKitStatus(
                enabled: true,
                state: unavailableState(for: service),
                serviceName: configuration.serviceName,
                apiBaseURL: apiBaseURL,
                recorderTargetURL: configuration.recorderTargetURL,
                lastError: message,
                readIssues: unavailableReadIssues(
                    for: service,
                    message: message
                )
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
                lastError: message,
                readIssues: [
                    RuntimeTestKitReadIssue(source: "containerAPI", message: message),
                ]
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
            lastError = configuration.apiEndpoint.unavailableDescription
            throw MacTestKitControllerError.apiEndpointUnavailable(lastError ?? "")
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

    private func unavailableReadIssues(
        for service: RuntimeContainerServiceObservation?,
        message: String
    ) -> [RuntimeTestKitReadIssue] {
        var issues = [
            RuntimeTestKitReadIssue(source: "testKitAPI", message: message),
        ]
        guard let service else {
            issues.append(RuntimeTestKitReadIssue(
                source: "containerService",
                message: "TestKit container service observation is missing for \(configuration.serviceName)."
            ))
            return issues
        }
        if service.state == nil {
            issues.append(RuntimeTestKitReadIssue(
                source: "containerService.state",
                message: "TestKit container service state is not reported for \(configuration.serviceName)."
            ))
        }
        if service.health == nil {
            issues.append(RuntimeTestKitReadIssue(
                source: "containerService.health",
                message: "TestKit container service health is not reported for \(configuration.serviceName)."
            ))
        }
        return issues
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
        await apiHealthCheck(apiBaseURL)
    }

    private static func defaultAPIHealthCheck(apiBaseURL: String) async -> Bool {
        do {
            var request = URLRequest(
                url: URL(string: "\(apiBaseURL)/health")!,
                timeoutInterval: 5
            )
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
            guard let message = String(data: data, encoding: .utf8) else {
                throw MacTestKitControllerError.requestFailed(
                    "HTTP \(httpResponse.statusCode) response body is not valid UTF-8"
                )
            }
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

public enum MacTestKitAPIEndpointSource: Equatable, Sendable {
    case explicit(baseURL: String)
    case runtimeStatusVMIP(port: Int)

    func baseURL(from status: RuntimeStatus) -> String? {
        switch self {
        case .explicit(let baseURL):
            let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return normalized.isEmpty ? nil : normalized
        case .runtimeStatusVMIP(let port):
            guard let vmIP = status.vmIP, !vmIP.isEmpty else {
                return nil
            }
            return "http://\(vmIP):\(port)"
        }
    }

    var unavailableDescription: String {
        switch self {
        case .explicit:
            return "TestKit container API endpoint is not configured."
        case .runtimeStatusVMIP:
            return "TestKit container API is unavailable because the VM IP is not known yet."
        }
    }
}

public struct MacTestKitControllerConfiguration: Equatable, Sendable {
    public let enabled: Bool
    public let serviceName: String
    public let apiEndpoint: MacTestKitAPIEndpointSource
    public let recorderTargetURL: String

    public init(
        enabled: Bool = false,
        serviceName: String = "testkit",
        apiEndpoint: MacTestKitAPIEndpointSource = .runtimeStatusVMIP(port: 18322),
        recorderTargetURL: String = "http://edge/"
    ) {
        self.enabled = enabled
        self.serviceName = serviceName
        self.apiEndpoint = apiEndpoint
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

