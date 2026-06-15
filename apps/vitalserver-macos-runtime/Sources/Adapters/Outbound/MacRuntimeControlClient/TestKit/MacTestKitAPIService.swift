import Foundation
import Contracts
import RuntimeControl

struct MacTestKitAPIService {
    var configuration: MacTestKitControllerConfiguration
    var apiClient: MacTestKitAPIClient

    func health(apiBaseURL: String) async -> MacTestKitAPIHealthRead {
        await apiClient.health(apiBaseURL: apiBaseURL)
    }

    func loadSessions(apiBaseURL: String) async throws -> [RuntimeTestKitSession] {
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/sessions")
        urlRequest.httpMethod = "GET"
        let response = try await apiClient.decode(TestKitSessionsResponse.self, from: urlRequest)
        return response.sessions
    }

    func loadBeds(apiBaseURL: String) async throws -> [RuntimeTestKitBed] {
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/beds")
        urlRequest.httpMethod = "GET"
        let response = try await apiClient.decode(TestKitBedsResponse.self, from: urlRequest)
        return response.beds
    }

    func createBeds(
        _ request: RuntimeTestKitCreateBedsRequest,
        apiBaseURL: String
    ) async throws -> [RuntimeTestKitBed] {
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/beds")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let response = try await apiClient.decode(TestKitBedsResponse.self, from: urlRequest)
        return response.beds
    }

    func deleteBeds(
        _ request: RuntimeTestKitDeleteBedsRequest,
        apiBaseURL: String
    ) async throws -> [RuntimeTestKitBed] {
        let requestBody = TestKitDeleteBedsRequest(
            targetURL: configuration.recorderTargetURL,
            roomNames: request.roomNames
        )
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/beds/delete")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let response = try await apiClient.decode(TestKitBedsResponse.self, from: urlRequest)
        return response.beds
    }

    func resetBeds(apiBaseURL: String) async throws -> [RuntimeTestKitBed] {
        var urlRequest = try apiClient.request(
            apiBaseURL: apiBaseURL,
            path: "/beds",
            queryItems: [
                URLQueryItem(name: "targetUrl", value: configuration.recorderTargetURL)
            ]
        )
        urlRequest.httpMethod = "DELETE"

        let response = try await apiClient.decode(TestKitBedsResponse.self, from: urlRequest)
        return response.beds
    }

    func startSession(
        _ request: RuntimeTestKitVirtualRecorderStartRequest,
        apiBaseURL: String
    ) async throws -> RuntimeTestKitSession {
        let requestBody = TestKitStartSessionRequest(
            runtimeRequest: request,
            targetURL: configuration.recorderTargetURL
        )
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/sessions")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        return try await apiClient.decode(RuntimeTestKitSession.self, from: urlRequest)
    }

    func sessionAction(
        apiBaseURL: String,
        sessionID: String,
        pathComponent: String
    ) async throws -> RuntimeTestKitSession {
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/sessions/\(sessionID)/\(pathComponent)")
        urlRequest.httpMethod = "POST"
        return try await apiClient.decode(RuntimeTestKitSession.self, from: urlRequest)
    }

    func restartSession(
        apiBaseURL: String,
        sessionID: String,
        bedRoomNames: [String]
    ) async throws -> RuntimeTestKitSession {
        let requestBody = TestKitRestartSessionRequest(bedRoomNames: bedRoomNames)
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/sessions/\(sessionID)/restart")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        return try await apiClient.decode(RuntimeTestKitSession.self, from: urlRequest)
    }

    func deleteSession(apiBaseURL: String, sessionID: String) async throws -> RuntimeTestKitSession {
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/sessions/\(sessionID)")
        urlRequest.httpMethod = "DELETE"
        return try await apiClient.decode(RuntimeTestKitSession.self, from: urlRequest)
    }

    func deleteRecorder(apiBaseURL: String, vrcode: String) async throws -> RuntimeTestKitRecorderDeletion {
        let requestBody = TestKitDeleteRecorderRequest(
            targetURL: configuration.recorderTargetURL,
            vrcode: vrcode
        )
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/recorders/delete")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        return try await apiClient.decode(RuntimeTestKitRecorderDeletion.self, from: urlRequest)
    }

    func resetSessions(apiBaseURL: String) async throws {
        var urlRequest = try apiClient.request(apiBaseURL: apiBaseURL, path: "/sessions")
        urlRequest.httpMethod = "DELETE"
        _ = try await apiClient.decode(TestKitSessionsResponse.self, from: urlRequest)
    }
}
