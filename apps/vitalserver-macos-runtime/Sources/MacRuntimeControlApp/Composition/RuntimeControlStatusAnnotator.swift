import Foundation
import RuntimeControl

struct RuntimeControlStatusAnnotator {
    let runtimeControlHTTP: String
    let runtimeControlStartedAt: String

    init(runtimeControlHTTP: String = "200", runtimeControlStartedAt: Date = Date()) {
        self.runtimeControlHTTP = runtimeControlHTTP
        self.runtimeControlStartedAt = Self.timestamp(runtimeControlStartedAt)
    }

    func annotated(_ status: RuntimeStatus) -> RuntimeStatus {
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
