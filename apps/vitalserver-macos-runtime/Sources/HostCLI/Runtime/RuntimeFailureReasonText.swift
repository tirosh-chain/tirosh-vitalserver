import Core
import Contracts

enum RuntimeFailureReasonText {
    static func describe(_ reasons: [RuntimeFailureReason]) -> String {
        reasons.isEmpty ? "no failure reason reported" : reasons.map(\.rawValue).joined(separator: ", ")
    }
}
