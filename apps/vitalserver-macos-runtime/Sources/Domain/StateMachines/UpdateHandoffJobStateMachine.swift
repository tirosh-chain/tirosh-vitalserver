import Contracts

public enum UpdateHandoffJobEvent: Equatable, Sendable {
    case launchClaimed(launchId: String, observedAt: String)
    case childStarted(UpdateHandoffChildIdentity, observedAt: String)
    case childCompleted(
        UpdateHandoffChildCompletionReceipt,
        observedAt: String
    )
    case cancellationRequested(observedAt: String)
    case processTreeTerminated(reason: String, observedAt: String)
    case childCompletionUnavailable(reason: String, observedAt: String)
}

public enum UpdateHandoffJobTransitionError: Error, Equatable, Sendable {
    case invalidSchemaVersion(String)
    case invalidRevision(Int)
    case invalidTransition(state: UpdateHandoffJobState, event: String)
    case missingLaunchId
    case childIdentityMismatch
    case invalidCompletionReceipt
}

public enum UpdateHandoffJobStateMachine {
    public static func enqueue(
        jobId: String,
        updateId: String,
        operationId: String,
        invocationPath: String,
        updaterPath: String,
        observedAt: String
    ) -> UpdateHandoffJobDocument {
        UpdateHandoffJobDocument(
            jobId: jobId,
            revision: 1,
            updateId: updateId,
            operationId: operationId,
            invocationPath: invocationPath,
            updaterPath: updaterPath,
            launchId: nil,
            state: .queued,
            child: nil,
            completion: nil,
            createdAt: observedAt,
            updatedAt: observedAt
        )
    }

    public static func transition(
        _ job: UpdateHandoffJobDocument,
        event: UpdateHandoffJobEvent
    ) throws -> UpdateHandoffJobDocument {
        try validate(job)
        switch event {
        case .launchClaimed(let launchId, let observedAt):
            try require(job, state: .queued, event: "launch-claimed")
            guard !launchId.isEmpty else {
                throw UpdateHandoffJobTransitionError.missingLaunchId
            }
            return replacing(
                job,
                state: .launching,
                launchId: launchId,
                child: nil,
                completion: nil,
                observedAt: observedAt
            )
        case .childStarted(let child, let observedAt):
            try require(job, state: .launching, event: "child-started")
            guard job.launchId == child.launchId else {
                throw UpdateHandoffJobTransitionError.childIdentityMismatch
            }
            return replacing(
                job,
                state: .running,
                launchId: child.launchId,
                child: child,
                completion: nil,
                observedAt: observedAt
            )
        case .childCompleted(let receipt, let observedAt):
            guard job.state == .running || job.state == .cancellationRequested else {
                throw UpdateHandoffJobTransitionError.invalidTransition(
                    state: job.state,
                    event: "child-completed"
                )
            }
            guard let child = job.child,
                  receipt.jobId == job.jobId,
                  receipt.launchId == child.launchId,
                  receipt.processId == child.processId,
                  receipt.processGroupId == child.processGroupId,
                  (receipt.exitCode == nil) !=
                    (receipt.launchFailureReason == nil) else {
                throw UpdateHandoffJobTransitionError.invalidCompletionReceipt
            }
            let outcome: UpdateHandoffCompletionOutcome
            if job.state == .cancellationRequested {
                outcome = .interrupted
            } else if receipt.exitCode == 0 {
                outcome = .succeeded
            } else {
                outcome = .failed
            }
            let completion = UpdateHandoffJobCompletion(
                outcome: outcome,
                exitCode: receipt.exitCode,
                reason: receipt.launchFailureReason,
                finishedAt: receipt.finishedAt
            )
            return replacing(
                job,
                state: state(for: outcome),
                launchId: child.launchId,
                child: child,
                completion: completion,
                observedAt: observedAt
            )
        case .cancellationRequested(let observedAt):
            guard [.queued, .launching, .running].contains(job.state) else {
                throw UpdateHandoffJobTransitionError.invalidTransition(
                    state: job.state,
                    event: "cancellation-requested"
                )
            }
            return replacing(
                job,
                state: .cancellationRequested,
                launchId: job.launchId,
                child: job.child,
                completion: nil,
                observedAt: observedAt
            )
        case .processTreeTerminated(let reason, let observedAt):
            try require(
                job,
                state: .cancellationRequested,
                event: "process-tree-terminated"
            )
            return replacing(
                job,
                state: .interrupted,
                launchId: job.launchId,
                child: job.child,
                completion: UpdateHandoffJobCompletion(
                    outcome: .interrupted,
                    exitCode: nil,
                    reason: reason,
                    finishedAt: observedAt
                ),
                observedAt: observedAt
            )
        case .childCompletionUnavailable(let reason, let observedAt):
            guard job.state == .running || job.state == .launching else {
                throw UpdateHandoffJobTransitionError.invalidTransition(
                    state: job.state,
                    event: "child-completion-unavailable"
                )
            }
            return replacing(
                job,
                state: .interrupted,
                launchId: job.launchId,
                child: job.child,
                completion: UpdateHandoffJobCompletion(
                    outcome: .interrupted,
                    exitCode: nil,
                    reason: reason,
                    finishedAt: observedAt
                ),
                observedAt: observedAt
            )
        }
    }

    public static func validate(_ job: UpdateHandoffJobDocument) throws {
        guard job.schemaVersion == UpdateHandoffJobDocument.schemaVersion else {
            throw UpdateHandoffJobTransitionError.invalidSchemaVersion(
                job.schemaVersion
            )
        }
        guard job.revision > 0 else {
            throw UpdateHandoffJobTransitionError.invalidRevision(job.revision)
        }
    }

    private static func require(
        _ job: UpdateHandoffJobDocument,
        state: UpdateHandoffJobState,
        event: String
    ) throws {
        guard job.state == state else {
            throw UpdateHandoffJobTransitionError.invalidTransition(
                state: job.state,
                event: event
            )
        }
    }

    private static func state(
        for outcome: UpdateHandoffCompletionOutcome
    ) -> UpdateHandoffJobState {
        switch outcome {
        case .succeeded: .succeeded
        case .failed: .failed
        case .interrupted: .interrupted
        }
    }

    private static func replacing(
        _ job: UpdateHandoffJobDocument,
        state: UpdateHandoffJobState,
        launchId: String?,
        child: UpdateHandoffChildIdentity?,
        completion: UpdateHandoffJobCompletion?,
        observedAt: String
    ) -> UpdateHandoffJobDocument {
        UpdateHandoffJobDocument(
            schemaVersion: job.schemaVersion,
            jobId: job.jobId,
            revision: job.revision + 1,
            updateId: job.updateId,
            operationId: job.operationId,
            invocationPath: job.invocationPath,
            updaterPath: job.updaterPath,
            launchId: launchId,
            state: state,
            child: child,
            completion: completion,
            createdAt: job.createdAt,
            updatedAt: observedAt
        )
    }
}
