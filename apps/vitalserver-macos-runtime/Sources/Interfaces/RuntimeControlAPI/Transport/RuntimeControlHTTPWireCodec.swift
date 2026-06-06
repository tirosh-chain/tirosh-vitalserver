import Foundation

public enum RuntimeControlHTTPWireCodecError: Error, Equatable {
    case invalidRequest
    case unsupportedMethod(String)
    case invalidContentLength(String)
}

public enum RuntimeControlHTTPWireCodec {
    public static func requestIsComplete(_ data: Data) throws -> Bool {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }
        guard let headerRange = raw.range(of: "\r\n\r\n") else {
            return false
        }

        let headerText = String(raw[..<headerRange.lowerBound])
        let lines = headerText.components(separatedBy: "\r\n")
        let headers = try decodeHeaders(Array(lines.dropFirst()))
        guard let contentLengthValue = headerValue("Content-Length", in: headers) else {
            return true
        }
        guard let contentLength = Int(contentLengthValue), contentLength >= 0 else {
            throw RuntimeControlHTTPWireCodecError.invalidContentLength(contentLengthValue)
        }

        let bodyText = String(raw[headerRange.upperBound...])
        return Data(bodyText.utf8).count >= contentLength
    }

    public static func decodeRequest(_ data: Data) throws -> RuntimeControlHTTPRequest {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }
        guard let headerRange = raw.range(of: "\r\n\r\n") else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }

        let headerText = String(raw[..<headerRange.lowerBound])
        let bodyStart = headerRange.upperBound
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw RuntimeControlHTTPWireCodecError.invalidRequest
        }
        guard let method = RuntimeControlHTTPMethod(rawValue: requestParts[0]) else {
            throw RuntimeControlHTTPWireCodecError.unsupportedMethod(requestParts[0])
        }

        let headers = try decodeHeaders(Array(lines.dropFirst()))
        let body = try decodeBody(raw: raw, bodyStart: bodyStart, headers: headers)
        return RuntimeControlHTTPRequest(method: method, path: requestParts[1], headers: headers, body: body)
    }

    public static func encodeResponse(_ response: RuntimeControlHTTPResponse) -> Data {
        let body = response.body ?? Data()
        var headers = response.headers
        headers["Content-Length"] = String(body.count)
        headers["Connection"] = "close"

        var head = "HTTP/1.1 \(response.status.rawValue) \(reasonPhrase(for: response.status))\r\n"
        for key in headers.keys.sorted() {
            guard let value = headers[key] else {
                continue
            }
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    public static func encodeStreamHeader(status: RuntimeControlHTTPStatus, headers: [String: String]) -> Data {
        var streamHeaders = headers
        streamHeaders["Connection"] = "keep-alive"

        var head = "HTTP/1.1 \(status.rawValue) \(reasonPhrase(for: status))\r\n"
        for key in streamHeaders.keys.sorted() {
            guard let value = streamHeaders[key] else {
                continue
            }
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8)
    }

    public static func badRequestResponse(message: String) -> RuntimeControlHTTPResponse {
        return RuntimeControlHTTPResponse(
            status: .badRequest,
            headers: ["Content-Type": "application/json"],
            body: RuntimeControlErrorResponseEncoder.encode(code: .badRequest, message: message)
        )
    }

    private static func decodeHeaders(_ lines: [String]) throws -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw RuntimeControlHTTPWireCodecError.invalidRequest
            }
            headers[parts[0]] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return headers
    }

    private static func decodeBody(raw: String, bodyStart: String.Index, headers: [String: String]) throws -> Data? {
        let bodyText = String(raw[bodyStart...])
        guard !bodyText.isEmpty else {
            return nil
        }

        guard let contentLengthValue = headerValue("Content-Length", in: headers) else {
            return Data(bodyText.utf8)
        }
        guard let contentLength = Int(contentLengthValue), contentLength >= 0 else {
            throw RuntimeControlHTTPWireCodecError.invalidContentLength(contentLengthValue)
        }

        let bodyData = Data(bodyText.utf8)
        return bodyData.prefix(contentLength)
    }

    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    private static func reasonPhrase(for status: RuntimeControlHTTPStatus) -> String {
        switch status {
        case .ok:
            return "OK"
        case .noContent:
            return "No Content"
        case .badRequest:
            return "Bad Request"
        case .unauthorized:
            return "Unauthorized"
        case .notFound:
            return "Not Found"
        case .methodNotAllowed:
            return "Method Not Allowed"
        case .notImplemented:
            return "Not Implemented"
        case .internalServerError:
            return "Internal Server Error"
        }
    }
}
