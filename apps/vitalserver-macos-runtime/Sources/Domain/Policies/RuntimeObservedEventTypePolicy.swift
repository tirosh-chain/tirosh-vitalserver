import Contracts
import Errors

public enum RuntimeObservedEventTypePolicy {
    public static func eventType(
        for snapshot: RuntimeHealthSnapshot,
        defaultEventType: RuntimeEventType = .statusChanged
    ) -> RuntimeEventType {
        if !snapshot.vmErrors.isEmpty {
            return .vmErrorObserved
        }
        if !snapshot.failureReasons.isEmpty {
            return .domainErrorObserved
        }
        return defaultEventType
    }
}
