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
    public let proxyServiceRequired: Bool
    public let watchdogServiceRequired: Bool
    public let vmServiceLoaded: Bool
    public let proxyServiceLoaded: Bool
    public let watchdogServiceLoaded: Bool
    public let snapshot: RuntimeHealthSnapshot

    public init(
        vmServiceRequired: Bool,
        proxyServiceRequired: Bool,
        watchdogServiceRequired: Bool,
        vmServiceLoaded: Bool,
        proxyServiceLoaded: Bool,
        watchdogServiceLoaded: Bool,
        snapshot: RuntimeHealthSnapshot
    ) {
        self.vmServiceRequired = vmServiceRequired
        self.proxyServiceRequired = proxyServiceRequired
        self.watchdogServiceRequired = watchdogServiceRequired
        self.vmServiceLoaded = vmServiceLoaded
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
        var lastReasons: [RuntimeFailureReason] = []

        for attempt in 0..<configuration.maxAttempts {
            let observation = observe()
            let pendingServiceReasons = pendingRequiredServiceReasons(observation)
            if !pendingServiceReasons.isEmpty {
                lastReasons = pendingServiceReasons
                publishProgressIfNeeded(
                    attempt: attempt,
                    configuration: configuration,
                    reasons: pendingServiceReasons,
                    onProgress: onProgress
                )
                sleep()
                continue
            }

            if let bootstrapFailure = observation.snapshot.failureReasons.first(where: { $0.isGuestBootstrapFailure }) {
                return .failedEarly(bootstrapFailure)
            }
            if RuntimeHealthSnapshotPolicy.isHealthy(observation.snapshot) {
                return .healthy
            }

            lastReasons = observation.snapshot.failureReasons
            publishProgressIfNeeded(
                attempt: attempt,
                configuration: configuration,
                reasons: observation.snapshot.failureReasons,
                onProgress: onProgress
            )
            sleep()
        }

        return .timedOut(lastReasons)
    }

    private static func pendingRequiredServiceReasons(_ observation: RuntimeHealthWaitObservation) -> [RuntimeFailureReason] {
        if observation.vmServiceRequired, !observation.vmServiceLoaded {
            return [.vmService("not-loaded")]
        }
        if observation.proxyServiceRequired, !observation.proxyServiceLoaded {
            return [.proxyService("not-loaded")]
        }
        if observation.watchdogServiceRequired, !observation.watchdogServiceLoaded {
            return [.watchdogService("not-loaded")]
        }
        return []
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
