import RuntimeCore
import RuntimeContracts

enum RuntimeFailureReasonText {
    static func describe(_ reasons: [RuntimeFailureReason]) -> String {
        reasons.isEmpty ? "unknown" : reasons.map(\.rawValue).joined(separator: ", ")
    }
}
