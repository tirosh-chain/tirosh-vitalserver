import Contracts

public enum RuntimeHealthSnapshotPolicy {
    public static let missingFailureReasons = "runtime-health-snapshot-missing-failure-reasons"

    public static func isHealthy(_ snapshot: RuntimeHealthSnapshot) -> Bool {
        snapshot.failureReasons.isEmpty && missingFailureReasonIssue(snapshot) == nil
    }

    public static func missingFailureReasonIssue(_ snapshot: RuntimeHealthSnapshot) -> String? {
        guard snapshot.failureReasons.isEmpty,
              hasExplicitFailureState(snapshot)
        else {
            return nil
        }
        return missingFailureReasons
    }

    private static func hasExplicitFailureState(_ snapshot: RuntimeHealthSnapshot) -> Bool {
        snapshot.vmExecutable != .executable
            || snapshot.proxyExecutable != .executable
            || snapshot.rootfsBase != .present
            || snapshot.vmDisk != .present
            || snapshot.vmService != .loaded
            || snapshot.proxyService != .loaded
            || snapshot.watchdogService != .loaded
            || !snapshot.vmErrors.isEmpty
            || !isSuccessfulHTTPStatus(snapshot.hostProxyHTTP)
            || hasGuestHTTPFailure(snapshot.guestHTTP)
            || hasCriticalObservationFailure(snapshot)
    }

    private static func hasCriticalObservationFailure(_ snapshot: RuntimeHealthSnapshot) -> Bool {
        !RuntimeObservationHealthPolicy.failureReasons(
            guestServiceStatuses: snapshot.guestServiceStatuses,
            guestServiceResources: snapshot.guestServiceResources,
            guestServiceResourceReadIssues: snapshot.guestServiceResourceReadIssues
        ).isEmpty
    }

    private static func hasGuestHTTPFailure(_ value: String) -> Bool {
        value != RuntimeHTTPStatusText.notRead && !isSuccessfulHTTPStatus(value)
    }

    private static func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}
