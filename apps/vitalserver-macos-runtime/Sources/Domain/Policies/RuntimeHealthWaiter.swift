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

public struct RuntimeHealthWaitState: Equatable {
    public let accumulatedReasons: [RuntimeFailureReason]

    public init(accumulatedReasons: [RuntimeFailureReason] = []) {
        self.accumulatedReasons = accumulatedReasons
    }
}

public struct RuntimeHealthWaitProgress: Equatable {
    public let reasons: [RuntimeFailureReason]

    public init(reasons: [RuntimeFailureReason]) {
        self.reasons = reasons
    }
}

public enum RuntimeHealthWaitAttemptOutcome: Equatable {
    case healthy
    case failedEarly(RuntimeFailureReason)
    case waiting(state: RuntimeHealthWaitState, progress: RuntimeHealthWaitProgress?)
}

public enum RuntimeHealthWaiter {
    public static func evaluateAttempt(
        configuration: RuntimeHealthWaitConfiguration,
        attempt: Int,
        state: RuntimeHealthWaitState,
        observation: RuntimeHealthWaitObservation
    ) -> RuntimeHealthWaitAttemptOutcome {
        let pendingServiceReasons = pendingRequiredServiceReasons(observation)
        let snapshotReasons = explicitSnapshotFailureReasons(observation.snapshot)
        let currentReasons = uniqueReasons(pendingServiceReasons + snapshotReasons)

        if let bootstrapFailure = currentReasons.first(where: { $0.isGuestBootstrapFailure }) {
            return .failedEarly(bootstrapFailure)
        }

        if pendingServiceReasons.isEmpty, RuntimeHealthSnapshotPolicy.isHealthy(observation.snapshot) {
            return .healthy
        }

        let nextState = RuntimeHealthWaitState(
            accumulatedReasons: uniqueReasons(state.accumulatedReasons + currentReasons)
        )
        let progress = shouldPublishProgress(attempt: attempt, configuration: configuration)
            ? RuntimeHealthWaitProgress(reasons: currentReasons)
            : nil
        return .waiting(state: nextState, progress: progress)
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
        case .platformAgent:
            return .unknown("platform-agent-service-\(stateToken)")
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

    private static func shouldPublishProgress(
        attempt: Int,
        configuration: RuntimeHealthWaitConfiguration
    ) -> Bool {
        attempt == 0 || attempt % configuration.progressEveryAttempts == 0
    }
}

extension RuntimeFailureReason {
    public var isGuestBootstrapFailure: Bool {
        rawValue.hasPrefix("guest-bootstrap-")
    }
}
