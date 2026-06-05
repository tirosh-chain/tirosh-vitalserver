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
    public let requiredServices: [RuntimeManagedService]
    public let serviceStates: [RuntimeManagedService: RuntimeServiceState]
    public let snapshot: RuntimeHealthSnapshot

    public init(
        requiredServices: [RuntimeManagedService],
        serviceStates: [RuntimeManagedService: RuntimeServiceState],
        snapshot: RuntimeHealthSnapshot
    ) {
        self.requiredServices = requiredServices
        self.serviceStates = serviceStates
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
        observation.requiredServices.compactMap { service in
            guard let state = observation.serviceStates[service] else {
                return serviceFailureReason(service, state: nil)
            }
            guard state != .loaded else {
                return nil
            }
            return serviceFailureReason(service, state: state)
        }
    }

    private static func serviceFailureReason(
        _ service: RuntimeManagedService,
        state: RuntimeServiceState?
    ) -> RuntimeFailureReason {
        let stateToken = serviceStateFailureToken(state)
        switch service {
        case .vm:
            return .vmService(stateToken)
        case .guestLogSync:
            return .guestLogSyncService(stateToken)
        case .proxy:
            return .proxyService(stateToken)
        case .watchdog:
            return .watchdogService(stateToken)
        case .sleepPrevention:
            return .unknown("sleep-prevention-service-\(stateToken)")
        }
    }

    private static func serviceStateFailureToken(_ state: RuntimeServiceState?) -> String {
        guard let state else {
            return "missing"
        }
        switch state {
        case .loaded:
            return "loaded"
        case .notLoaded:
            return "not-loaded"
        case .readFailed(let reason):
            return reason.isEmpty ? "read-failed" : "read-failed:\(reason)"
        case .permissionDenied(let reason):
            return reason.isEmpty ? "permission-denied" : "permission-denied:\(reason)"
        case .unknown(let value):
            return value.isEmpty ? "unknown" : "unknown:\(value)"
        }
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
