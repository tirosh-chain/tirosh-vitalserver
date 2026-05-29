import Contracts

public enum RuntimeHealthSnapshotPolicy {
    public static func isHealthy(_ snapshot: RuntimeHealthSnapshot) -> Bool {
        snapshot.failureReasons.isEmpty
    }
}
