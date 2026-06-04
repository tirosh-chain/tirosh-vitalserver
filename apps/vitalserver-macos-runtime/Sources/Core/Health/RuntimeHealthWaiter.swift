import Contracts
public struct RuntimeHealthWaitConfiguration: Equatable {
    public let maxAttempts: Int
    public let progressEveryAttempts: Int

    public init(maxAttempts: Int, progressEveryAttempts: Int) {
        self.maxAttempts = maxAttempts
        self.progressEveryAttempts = max(progressEveryAttempts, 1)
    }
}

public struct RuntimeHealthWaitObservation: Equatable {
    public let vmServiceRequired: Bool
    public let guestLogSyncServiceRequired: Bool
    public let proxyServiceRequired: Bool
    public let watchdogServiceRequired: Bool
    public let vmServiceLoaded: Bool
    public let guestLogSyncServiceLoaded: Bool
    public let proxyServiceLoaded: Bool
    public let watchdogServiceLoaded: Bool
    public let snapshot: RuntimeHealthSnapshot

    public init(
        vmServiceRequired: Bool,
        guestLogSyncServiceRequired: Bool,
        proxyServiceRequired: Bool,
        watchdogServiceRequired: Bool,
        vmServiceLoaded: Bool,
        guestLogSyncServiceLoaded: Bool,
        proxyServiceLoaded: Bool,
        watchdogServiceLoaded: Bool,
        snapshot: RuntimeHealthSnapshot
    ) {
        self.vmServiceRequired = vmServiceRequired
        self.guestLogSyncServiceRequired = guestLogSyncServiceRequired
        self.proxyServiceRequired = proxyServiceRequired
        self.watchdogServiceRequired = watchdogServiceRequired
        self.vmServiceLoaded = vmServiceLoaded
        self.guestLogSyncServiceLoaded = guestLogSyncServiceLoaded
        self.proxyServiceLoaded = proxyServiceLoaded
        self.watchdogServiceLoaded = watchdogServiceLoaded
        self.snapshot = snapshot
    }
}

public enum RuntimeHealthWaitResult: Equatable {
    case healthy
    case failedEarly(RuntimeFailureReason)
    case timedOut([RuntimeFailureReason])
}

public enum RuntimeHealthWaiter {
    public static func wait(
        configuration: RuntimeHealthWaitConfiguration,
        observe: () -> RuntimeHealthWaitObservation,
        onProgress: ([RuntimeFailureReason]) -> Void,
        sleep: () -> Void
    ) -> RuntimeHealthWaitResult {
        var accumulatedReasons: [RuntimeFailureReason] = []

        for attempt in 0..<configuration.maxAttempts {
            let observation = observe()
            let pendingServiceReasons = pendingRequiredServiceReasons(observation)
            let snapshotReasons = explicitSnapshotFailureReasons(observation.snapshot)
            let currentReasons = uniqueReasons(pendingServiceReasons + snapshotReasons)

            if let bootstrapFailure = currentReasons.first(where: { $0.isGuestBootstrapFailure }) {
                return .failedEarly(bootstrapFailure)
            }

            if !pendingServiceReasons.isEmpty {
                accumulatedReasons = uniqueReasons(accumulatedReasons + currentReasons)
                publishProgressIfNeeded(
                    attempt: attempt,
                    configuration: configuration,
                    reasons: currentReasons,
                    onProgress: onProgress
                )
                sleep()
                continue
            }

            if RuntimeHealthSnapshotPolicy.isHealthy(observation.snapshot) {
                return .healthy
            }

            accumulatedReasons = uniqueReasons(accumulatedReasons + currentReasons)
            publishProgressIfNeeded(
                attempt: attempt,
                configuration: configuration,
                reasons: currentReasons,
                onProgress: onProgress
            )
            sleep()
        }

        return .timedOut(accumulatedReasons)
    }

    private static func pendingRequiredServiceReasons(_ observation: RuntimeHealthWaitObservation) -> [RuntimeFailureReason] {
        if observation.vmServiceRequired, !observation.vmServiceLoaded {
            return [.vmService("not-loaded")]
        }
        if observation.guestLogSyncServiceRequired, !observation.guestLogSyncServiceLoaded {
            return [.guestLogSyncService("not-loaded")]
        }
        if observation.proxyServiceRequired, !observation.proxyServiceLoaded {
            return [.proxyService("not-loaded")]
        }
        if observation.watchdogServiceRequired, !observation.watchdogServiceLoaded {
            return [.watchdogService("not-loaded")]
        }
        return []
    }

    private static func explicitSnapshotFailureReasons(_ snapshot: RuntimeHealthSnapshot) -> [RuntimeFailureReason] {
        if let missingIssue = RuntimeHealthSnapshotPolicy.missingFailureReasonIssue(snapshot) {
            return [.unknown(missingIssue)]
        }
        return snapshot.failureReasons
    }

    private static func uniqueReasons(_ reasons: [RuntimeFailureReason]) -> [RuntimeFailureReason] {
        var result: [RuntimeFailureReason] = []
        for reason in reasons where !result.contains(reason) {
            result.append(reason)
        }
        return result
    }

    private static func publishProgressIfNeeded(
        attempt: Int,
        configuration: RuntimeHealthWaitConfiguration,
        reasons: [RuntimeFailureReason],
        onProgress: ([RuntimeFailureReason]) -> Void
    ) {
        if attempt == 0 || attempt % configuration.progressEveryAttempts == 0 {
            onProgress(reasons)
        }
    }
}

extension RuntimeFailureReason {
    public var isGuestBootstrapFailure: Bool {
        rawValue.hasPrefix("guest-bootstrap-")
    }
}
