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
        var urlRequest = try apiClient.request(
            apiBaseURL: apiBaseURL,
            path: "/sessions",
            timeout: .longRunningCommand
        )
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
        bedroomName: String?
    ) async throws -> RuntimeTestKitSession {
        let requestBody = TestKitRestartSessionRequest(bedroomName: bedroomName)
        var urlRequest = try apiClient.request(
            apiBaseURL: apiBaseURL,
            path: "/sessions/\(sessionID)/restart",
            timeout: .longRunningCommand
        )
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

    func uploadVitalFile(
        fileURL: URL,
        bedRoomName: String,
        vitalServerBaseURL: String,
        endpoint: String
    ) async throws -> RuntimeTestKitVitalFileUploadFileResult {
        let fileSize = try fileSizeBytes(fileURL)
        let boundary = "----tirosh-vitalserver-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let filename = fileURL.lastPathComponent
        let header = multipartHeader(boundary: boundary, filename: filename)
        let footer = "\r\n--\(boundary)--\r\n".data(using: .utf8) ?? Data()
        let contentLength = Int64(header.count) + fileSize + Int64(footer.count)
        let bodyFileURL = try multipartBodyFile(header: header, fileURL: fileURL, footer: footer)
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }
        var request = try apiClient.request(
            apiBaseURL: vitalServerBaseURL,
            path: endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)",
            timeout: .longRunningCommand
        )
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(contentLength), forHTTPHeaderField: "Content-Length")

        let startedAt = Date()
        do {
            let (data, response) = try await apiClient.send(request, bodyFileURL: bodyFileURL)
            let elapsed = Date().timeIntervalSince(startedAt)
            let ok = (200..<300).contains(response.statusCode)
            return RuntimeTestKitVitalFileUploadFileResult(
                path: fileURL.path,
                filename: filename,
                bedRoomName: bedRoomName,
                sizeBytes: fileSize,
                statusCode: response.statusCode,
                ok: ok,
                elapsedSeconds: elapsed,
                error: ok ? nil : responseError(statusCode: response.statusCode, body: data)
            )
        } catch {
            return RuntimeTestKitVitalFileUploadFileResult(
                path: fileURL.path,
                filename: filename,
                bedRoomName: bedRoomName,
                sizeBytes: fileSize,
                statusCode: 0,
                ok: false,
                elapsedSeconds: Date().timeIntervalSince(startedAt),
                error: error.localizedDescription
            )
        }
    }

    private func multipartHeader(boundary: String, filename: String) -> Data {
        let escapedFilename = filename.replacingOccurrences(of: "\"", with: "%22")
        let value = [
            "--\(boundary)",
            "Content-Disposition: form-data; name=\"vitalfile\"; filename=\"\(escapedFilename)\"",
            "Content-Type: application/octet-stream",
            "",
            "",
        ].joined(separator: "\r\n")
        return value.data(using: .utf8) ?? Data()
    }

    private func multipartBodyFile(header: Data, fileURL: URL, footer: Data) throws -> URL {
        let bodyFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tirosh-vital-upload-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: bodyFileURL.path, contents: nil)
        do {
            let output = try FileHandle(forWritingTo: bodyFileURL)
            defer { try? output.close() }
            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }

            try output.write(contentsOf: header)
            while true {
                let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
                if chunk.isEmpty {
                    break
                }
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: footer)
            return bodyFileURL
        } catch {
            try? FileManager.default.removeItem(at: bodyFileURL)
            throw error
        }
    }

    private func fileSizeBytes(_ fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw MacTestKitControllerError.requestFailed("File size is not available: \(fileURL.path)")
        }
        return size.int64Value
    }

    private func responseError(statusCode: Int, body: Data) -> String {
        let message = String(data: body.prefix(512), encoding: .utf8) ?? ""
        return message.isEmpty ? "HTTP \(statusCode)" : "HTTP \(statusCode): \(message)"
    }
}
