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

    /// Parses the public Guest Control operation-ledger query. It must not use
    /// `RuntimeEventQuery`: that model also admits Host diagnostics event types
    /// which the Guest ledger does not own.
    func runtimeOperationEventQuery() throws -> RuntimeOperationEventQuery {
        let limit: Int
        if let rawLimit = try queryValue(named: "limit") {
            guard let parsedLimit = Int(rawLimit),
                  parsedLimit > 0,
                  parsedLimit <= RuntimeOperationEventQuery.maximumLimit else {
                throw RuntimeControlHTTPQueryError.invalidLimit(rawLimit)
            }
            limit = parsedLimit
        } else {
            limit = RuntimeOperationEventQuery.defaultLimit
        }

        // The Guest ledger owns the cursor format. The Host proxy keeps it
        // opaque and forwards the exact token returned by the prior response.
        let cursor = try queryValue(named: "cursor")

        let eventType: RuntimeOperationEventType?
        if let rawEventType = try queryValue(named: "type") {
            guard let parsed = RuntimeOperationEventType(rawValue: rawEventType) else {
                throw RuntimeControlHTTPQueryError.invalidEventType(rawEventType)
            }
            eventType = parsed
        } else {
            eventType = nil
        }

        return RuntimeOperationEventQuery(
            limit: limit,
            eventType: eventType,
            since: try queryValue(named: "since"),
            cursor: cursor
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
        guard components.count == 4,
              components[0] == "runtime",
              components[1] == "vitaldb",
              components[2] == "recorders",
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    func recorderObservabilityExpectationCode() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 6,
              components[0] == "runtime",
              components[1] == "vitaldb",
              components[2] == "recorders",
              components[4] == "observability",
              components[5] == "expectation",
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    func recorderObservabilityDetailCode() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 5,
              components[0] == "runtime",
              components[1] == "vitaldb",
              components[2] == "recorders",
              components[4] == "observability",
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    func recorderObservabilityTimelineQuery() throws
        -> RuntimeRecorderObservabilityTimelineQuery {
        try requireOnlyQueryParameters(["from", "until", "bucketSeconds"])
        let vrcode = try recorderObservabilityHistoryCode(resource: "timeline")
        let (from, until) = try recorderObservabilityWindow(
            maximumSeconds: 24 * 60 * 60
        )
        guard let rawBucket = try queryValue(named: "bucketSeconds"),
              let bucket = Int(rawBucket),
              [300, 900, 3_600].contains(bucket) else {
            throw RuntimeControlHTTPQueryError.invalidQueryParameter(
                "bucketSeconds",
                (try queryValue(named: "bucketSeconds")) ?? "missing"
            )
        }
        return .init(
            vrcode: vrcode,
            from: from,
            until: until,
            bucketSeconds: bucket
        )
    }

    func recorderObservabilityIncidentQuery() throws
        -> RuntimeRecorderObservabilityIncidentQuery {
        try requireOnlyQueryParameters(["from", "until", "type", "cursor", "limit"])
        let vrcode = try recorderObservabilityHistoryCode(resource: "incidents")
        let (from, until) = try recorderObservabilityWindow(
            maximumSeconds: 30 * 24 * 60 * 60
        )
        let type = try queryValue(named: "type")
        if let type, !["panic", "oops", "watchdog", "lockup", "unknown"].contains(type) {
            throw RuntimeControlHTTPQueryError.invalidQueryParameter("type", type)
        }
        let rawLimit = try queryValue(named: "limit")
        let limit = rawLimit.flatMap(Int.init) ?? 50
        guard (1...100).contains(limit) else {
            throw RuntimeControlHTTPQueryError.invalidQueryParameter(
                "limit",
                rawLimit ?? "missing"
            )
        }
        return .init(
            vrcode: vrcode,
            from: from,
            until: until,
            type: type,
            cursor: try queryValue(named: "cursor"),
            limit: limit
        )
    }

    private func recorderObservabilityHistoryCode(resource: String) throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 6,
              components[0] == "runtime",
              components[1] == "vitaldb",
              components[2] == "recorders",
              components[4] == "observability",
              components[5] == Substring(resource),
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    private func recorderObservabilityWindow(
        maximumSeconds: TimeInterval
    ) throws -> (String, String) {
        guard let from = try queryValue(named: "from") else {
            throw RuntimeControlHTTPQueryError.missingQueryParameterValue("from")
        }
        guard let until = try queryValue(named: "until") else {
            throw RuntimeControlHTTPQueryError.missingQueryParameterValue("until")
        }
        guard let fromDate = Self.recorderObservabilityDate(from),
              let untilDate = Self.recorderObservabilityDate(until),
              untilDate > fromDate,
              untilDate.timeIntervalSince(fromDate) <= maximumSeconds else {
            throw RuntimeControlHTTPQueryError.invalidQueryParameter(
                "from/until",
                "\(from)/\(until)"
            )
        }
        return (from, until)
    }

    private func requireOnlyQueryParameters(_ allowed: Set<String>) throws {
        for item in try queryItems() where !allowed.contains(item.name) {
            throw RuntimeControlHTTPQueryError.invalidQueryParameter(
                item.name,
                item.value ?? "missing"
            )
        }
    }

    private static func recorderObservabilityDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func vitalDBRecorderActivityCode() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 5,
              components[0] == "runtime",
              components[1] == "vitaldb",
              components[2] == "recorders",
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty,
              components[4] == "activity"
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    func vitalDBRecorderVitalFilesCode() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 5,
              components[0] == "runtime",
              components[1] == "vitaldb",
              components[2] == "recorders",
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty,
              components[4] == "vital-files"
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("vrcode")
        }
        return decoded
    }

    func vitalDBBedID() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 4,
              components[0] == "runtime",
              components[1] == "vitaldb",
              components[2] == "beds",
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("bedID")
        }
        return decoded
    }

    func runtimeGuestServiceName() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 4,
              components[0] == "runtime",
              components[1] == "services",
              let decoded = String(components[2]).removingPercentEncoding,
              !decoded.isEmpty,
              ["status", "resource", "start", "stop", "restart"].contains(String(components[3]))
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("service")
        }
        return decoded
    }

    func runtimeLabSessionID() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 4,
              components[0] == "runtime",
              components[1] == "lab",
              components[2] == "sessions",
              let decoded = String(components[3]).removingPercentEncoding,
              !decoded.isEmpty
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("sessionId")
        }
        return decoded
    }

    func runtimeLabRecorderID() throws -> String {
        let components = RuntimeControlAPIEndpoint
            .normalizedPathForRequest(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 7,
              components[0] == "runtime",
              components[1] == "lab",
              components[2] == "sessions",
              components[4] == "recorders",
              let decoded = String(components[5]).removingPercentEncoding,
              !decoded.isEmpty,
              ["start", "stop"].contains(String(components[6]))
        else {
            throw RuntimeControlHTTPQueryError.invalidPathParameter("recorderId")
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
