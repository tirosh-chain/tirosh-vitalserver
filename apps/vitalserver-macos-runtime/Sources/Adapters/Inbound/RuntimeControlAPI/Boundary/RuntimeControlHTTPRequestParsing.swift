import Contracts
import Foundation
import RuntimeControl

public extension RuntimeControlHTTPRequest {
    func headerValue(named name: String) -> String? {
        headers.first { key, _ in
            key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }

    func queryValue(named name: String) throws -> String? {
        let matches = try queryItems().filter { item in
            item.name.caseInsensitiveCompare(name) == .orderedSame
        }
        guard matches.count <= 1 else {
            throw RuntimeControlHTTPQueryError.duplicateQueryParameter(name)
        }
        guard let item = matches.first else {
            return nil
        }
        guard let value = item.value else {
            throw RuntimeControlHTTPQueryError.missingQueryParameterValue(name)
        }
        return value
    }

    private func queryItems() throws -> [URLQueryItem] {
        guard let query = rawQueryString() else {
            return []
        }
        guard query.hasValidPercentEncoding else {
            throw RuntimeControlHTTPQueryError.invalidQueryString(query)
        }
        guard !query.isEmpty else {
            return []
        }
        guard let components = URLComponents(string: path), let queryItems = components.queryItems else {
            throw RuntimeControlHTTPQueryError.invalidQueryString(query)
        }
        return queryItems
    }

    private func rawQueryString() -> String? {
        guard let queryStart = path.firstIndex(of: "?") else {
            return nil
        }
        let afterQuestionMark = path.index(after: queryStart)
        let fragmentStart = path[afterQuestionMark...].firstIndex(of: "#") ?? path.endIndex
        return String(path[afterQuestionMark..<fragmentStart])
    }

    func runtimeEventQuery() throws -> RuntimeEventQuery {
        let limit: Int
        if let rawLimit = try queryValue(named: "limit") {
            guard let parsedLimit = Int(rawLimit), parsedLimit > 0 else {
                throw RuntimeControlHTTPQueryError.invalidLimit(rawLimit)
            }
            limit = parsedLimit
        } else {
            limit = RuntimeEventQuery.defaultLimit
        }

        let before: RuntimeEventCursor?
        if let rawCursor = try queryValue(named: "cursor") {
            guard let decodedCursor = RuntimeEventCursorWireCodec.decode(rawCursor) else {
                throw RuntimeControlHTTPQueryError.invalidCursor(rawCursor)
            }
            before = decodedCursor
        } else {
            before = nil
        }

        let eventType: RuntimeEventType?
        if let rawEventType = try queryValue(named: "type") {
            let parsedEventType = RuntimeEventType(rawValue: rawEventType)
            guard RuntimeEventType.knownTypes.contains(parsedEventType) else {
                throw RuntimeControlHTTPQueryError.invalidEventType(rawEventType)
            }
            eventType = parsedEventType
        } else {
            eventType = nil
        }

        return RuntimeEventQuery(
            limit: limit,
            eventType: eventType,
            since: try queryValue(named: "since"),
            before: before
        )
    }

    func runtimeLogTextRequest() throws -> RuntimeLogTextRequest {
        let source: RuntimeLogSource
        if let rawSource = try queryValue(named: "source") {
            guard let parsedSource = RuntimeLogSource(rawValue: rawSource) else {
                throw RuntimeControlHTTPQueryError.invalidLogSource(rawSource)
            }
            source = parsedSource
        } else {
            source = .helperMessage
        }

        let lineLimit: Int
        if let rawLimit = try queryValue(named: "lineLimit") {
            guard let parsedLimit = Int(rawLimit), parsedLimit > 0 else {
                throw RuntimeControlHTTPQueryError.invalidLimit(rawLimit)
            }
            lineLimit = parsedLimit
        } else {
            lineLimit = 200
        }

        return RuntimeLogTextRequest(
            source: source,
            lineLimit: lineLimit
        )
    }

    func vitalDBRecorderActivityWindowQuery() throws -> RuntimeVitalRecorderActivityWindowQuery {
        let vrcode = try vitalDBRecorderActivityCode()
        let bucketSeconds: Int
        if let rawBucketSeconds = try queryValue(named: "bucketSeconds") {
            guard let parsedBucketSeconds = Int(rawBucketSeconds) else {
                throw RuntimeControlHTTPQueryError.invalidQueryParameter("bucketSeconds", rawBucketSeconds)
            }
            bucketSeconds = parsedBucketSeconds
        } else {
            bucketSeconds = RuntimeVitalRecorderActivityWindowQuery.oneMinuteBucketSeconds
        }

        let period: RuntimeVitalRecorderActivityWindowPeriod
        if let rawPeriod = try queryValue(named: "period") {
            guard let parsedPeriod = RuntimeVitalRecorderActivityWindowPeriod(rawValue: rawPeriod) else {
                throw RuntimeControlHTTPQueryError.invalidQueryParameter("period", rawPeriod)
            }
            period = parsedPeriod
        } else {
            period = .lastHour
        }

        let pageIndex: Int?
        if let rawPageIndex = try queryValue(named: "pageIndex") {
            guard let parsedPageIndex = Int(rawPageIndex) else {
                throw RuntimeControlHTTPQueryError.invalidQueryParameter("pageIndex", rawPageIndex)
            }
            pageIndex = parsedPageIndex
        } else {
            pageIndex = nil
        }

        return RuntimeVitalRecorderActivityWindowQuery(
            vrcode: vrcode,
            bucketSeconds: bucketSeconds,
            period: period,
            pageIndex: pageIndex
        )
    }

    func decodedBody<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body else {
            throw RuntimeControlHTTPQueryError.missingBody
        }
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw RuntimeControlHTTPQueryError.invalidBody(
                "Decode failed for \(String(describing: type)): \(error.localizedDescription)"
            )
        }
    }

    func vitalDBRecorderCode() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 3,
              components[0] == "vitaldb",
              components[1] == "recorders",
              let decoded = String(components[2]).removingPercentEncoding,
              !decoded.isEmpty
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    private func vitalDBRecorderActivityCode() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 4,
              components[0] == "vitaldb",
              components[1] == "recorders",
              let decoded = String(components[2]).removingPercentEncoding,
              !decoded.isEmpty,
              components[3] == "activity"
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    func vitalDBBedID() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 3,
              components[0] == "vitaldb",
              components[1] == "beds",
              let decoded = String(components[2]).removingPercentEncoding,
              !decoded.isEmpty
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("bedID")
        }
        return decoded
    }
}

private extension String {
    var hasValidPercentEncoding: Bool {
        var index = startIndex
        while index < endIndex {
            guard self[index] == "%" else {
                formIndex(after: &index)
                continue
            }
            let first = self.index(after: index)
            guard first < endIndex else {
                return false
            }
            let second = self.index(after: first)
            guard second < endIndex,
                  self[first].isASCIIHexDigit,
                  self[second].isASCIIHexDigit else {
                return false
            }
            index = self.index(after: second)
        }
        return true
    }
}

private extension Character {
    var isASCIIHexDigit: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.allSatisfy { scalar in
                (48...57).contains(scalar.value)
                    || (65...70).contains(scalar.value)
                    || (97...102).contains(scalar.value)
            }
    }
}
