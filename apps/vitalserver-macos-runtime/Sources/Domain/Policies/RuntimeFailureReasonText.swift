import Contracts
import Errors

public enum RuntimeFailureReasonText {
    public static func describe(_ reasons: [RuntimeFailureReason]) -> String {
        reasons.isEmpty ? "no failure reason reported" : reasons.map(\.rawValue).joined(separator: ", ")
    }
}
