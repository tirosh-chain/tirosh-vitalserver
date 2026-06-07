import Foundation
import RuntimeControl
import Errors

public struct RuntimeControlStatusAnnotator {
    public let runtimeControlHTTP: String
    public let runtimeControlStartedAt: String

    public init(runtimeControlHTTP: String = "200", runtimeControlStartedAt: Date = Date()) {
        self.runtimeControlHTTP = runtimeControlHTTP
        self.runtimeControlStartedAt = Self.timestamp(runtimeControlStartedAt)
    }

    public func annotated(_ status: RuntimeStatus) -> RuntimeStatus {
        var next = status
        next.runtimeControlHTTP = runtimeControlHTTP
        next.runtimeControlStartedAt = runtimeControlStartedAt
        return next
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
