import Contracts
import Domain

public struct ManageUpdateHandoffJobUseCase {
    public init() {}

    public func enqueue(
        jobId: String,
        updateId: String,
        operationId: String,
        invocationPath: String,
        updaterPath: String,
        observedAt: String
    ) -> UpdateHandoffJobDocument {
        UpdateHandoffJobStateMachine.enqueue(
            jobId: jobId,
            updateId: updateId,
            operationId: operationId,
            invocationPath: invocationPath,
            updaterPath: updaterPath,
            observedAt: observedAt
        )
    }

    public func launchClaimed(
        job: UpdateHandoffJobDocument,
        launchId: String,
        observedAt: String
    ) throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            job,
            event: .launchClaimed(
                launchId: launchId,
                observedAt: observedAt
            )
        )
    }

    public func childStarted(
        job: UpdateHandoffJobDocument,
        child: UpdateHandoffChildIdentity,
        observedAt: String
    ) throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            job,
            event: .childStarted(child, observedAt: observedAt)
        )
    }

    public func childCompleted(
        job: UpdateHandoffJobDocument,
        receipt: UpdateHandoffChildCompletionReceipt,
        observedAt: String
    ) throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            job,
            event: .childCompleted(receipt, observedAt: observedAt)
        )
    }

    public func cancellationRequested(
        job: UpdateHandoffJobDocument,
        observedAt: String
    ) throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            job,
            event: .cancellationRequested(observedAt: observedAt)
        )
    }

    public func processTreeTerminated(
        job: UpdateHandoffJobDocument,
        reason: String,
        observedAt: String
    ) throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            job,
            event: .processTreeTerminated(
                reason: reason,
                observedAt: observedAt
            )
        )
    }

    public func childCompletionUnavailable(
        job: UpdateHandoffJobDocument,
        reason: String,
        observedAt: String
    ) throws -> UpdateHandoffJobDocument {
        try UpdateHandoffJobStateMachine.transition(
            job,
            event: .childCompletionUnavailable(
                reason: reason,
                observedAt: observedAt
            )
        )
    }
}
