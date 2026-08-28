import Application
import Contracts
import Foundation

public enum UpdateHandoffSupervisorWorkflowError:
    Error, Equatable, Sendable {
    case jobPersistenceFailed(
        jobId: String,
        expectedRevision: Int?,
        reason: String
    )
    case childLaunchFailed(jobId: String, launchId: String, reason: String)
    case startReceiptReadFailed(jobId: String, path: String, reason: String)
    case completionReceiptReadFailed(
        jobId: String,
        path: String,
        reason: String
    )
    case childObservationFailed(jobId: String, reason: String)
    case processTreeTerminationFailed(jobId: String, reason: String)
    case waitTimedOut(jobId: String, state: UpdateHandoffJobState)
}

public struct UpdateHandoffSupervisorWorkflowOperations {
    public let enqueue: (
        String, String, String, String, String, String
    ) -> UpdateHandoffJobDocument
    public let launchClaimed: (
        UpdateHandoffJobDocument, String, String
    ) throws -> UpdateHandoffJobDocument
    public let childStarted: (
        UpdateHandoffJobDocument, UpdateHandoffChildIdentity, String
    ) throws -> UpdateHandoffJobDocument
    public let childCompleted: (
        UpdateHandoffJobDocument,
        UpdateHandoffChildCompletionReceipt,
        String
    ) throws -> UpdateHandoffJobDocument
    public let cancellationRequested: (
        UpdateHandoffJobDocument, String
    ) throws -> UpdateHandoffJobDocument
    public let processTreeTerminated: (
        UpdateHandoffJobDocument, String, String
    ) throws -> UpdateHandoffJobDocument
    public let childCompletionUnavailable: (
        UpdateHandoffJobDocument, String, String
    ) throws -> UpdateHandoffJobDocument
    public let save: (UpdateHandoffJobDocument, Int?) throws -> Void
    public let launchChildOwner: (UpdateHandoffJobDocument) throws -> Void
    public let readStartReceipt: (
        UpdateHandoffJobDocument
    ) -> UpdateHandoffReceiptReadResult<UpdateHandoffChildStartReceipt>
    public let readCompletionReceipt: (
        UpdateHandoffJobDocument
    ) -> UpdateHandoffReceiptReadResult<UpdateHandoffChildCompletionReceipt>
    public let observeChild: (
        UpdateHandoffChildIdentity
    ) -> UpdateHandoffChildObservation
    public let terminateProcessTree: (
        UpdateHandoffChildIdentity
    ) -> UpdateHandoffProcessTreeTerminationResult
    public let makeId: () -> String
    public let now: () -> String
    public let describeFailure: (Error) -> String

    public init(
        enqueue: @escaping (
            String, String, String, String, String, String
        ) -> UpdateHandoffJobDocument,
        launchClaimed: @escaping (
            UpdateHandoffJobDocument, String, String
        ) throws -> UpdateHandoffJobDocument,
        childStarted: @escaping (
            UpdateHandoffJobDocument, UpdateHandoffChildIdentity, String
        ) throws -> UpdateHandoffJobDocument,
        childCompleted: @escaping (
            UpdateHandoffJobDocument,
            UpdateHandoffChildCompletionReceipt,
            String
        ) throws -> UpdateHandoffJobDocument,
        cancellationRequested: @escaping (
            UpdateHandoffJobDocument, String
        ) throws -> UpdateHandoffJobDocument,
        processTreeTerminated: @escaping (
            UpdateHandoffJobDocument, String, String
        ) throws -> UpdateHandoffJobDocument,
        childCompletionUnavailable: @escaping (
            UpdateHandoffJobDocument, String, String
        ) throws -> UpdateHandoffJobDocument,
        save: @escaping (UpdateHandoffJobDocument, Int?) throws -> Void,
        launchChildOwner: @escaping (UpdateHandoffJobDocument) throws -> Void,
        readStartReceipt: @escaping (
            UpdateHandoffJobDocument
        ) -> UpdateHandoffReceiptReadResult<UpdateHandoffChildStartReceipt>,
        readCompletionReceipt: @escaping (
            UpdateHandoffJobDocument
        ) -> UpdateHandoffReceiptReadResult<
            UpdateHandoffChildCompletionReceipt
        >,
        observeChild: @escaping (
            UpdateHandoffChildIdentity
        ) -> UpdateHandoffChildObservation,
        terminateProcessTree: @escaping (
            UpdateHandoffChildIdentity
        ) -> UpdateHandoffProcessTreeTerminationResult,
        makeId: @escaping () -> String,
        now: @escaping () -> String,
        describeFailure: @escaping (Error) -> String
    ) {
        self.enqueue = enqueue
        self.launchClaimed = launchClaimed
        self.childStarted = childStarted
        self.childCompleted = childCompleted
        self.cancellationRequested = cancellationRequested
        self.processTreeTerminated = processTreeTerminated
        self.childCompletionUnavailable = childCompletionUnavailable
        self.save = save
        self.launchChildOwner = launchChildOwner
        self.readStartReceipt = readStartReceipt
        self.readCompletionReceipt = readCompletionReceipt
        self.observeChild = observeChild
        self.terminateProcessTree = terminateProcessTree
        self.makeId = makeId
        self.now = now
        self.describeFailure = describeFailure
    }
}

public struct UpdateHandoffSupervisorWorkflow {
    public init() {}

    public func enqueue(
        jobId: String,
        updateId: String,
        operationId: String,
        invocationPath: String,
        updaterPath: String,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws -> UpdateHandoffJobDocument {
        let job = operations.enqueue(
            jobId,
            updateId,
            operationId,
            invocationPath,
            updaterPath,
            operations.now()
        )
        try persist(job, expectedRevision: nil, operations: operations)
        return job
    }

    public func reconcile(
        _ job: UpdateHandoffJobDocument,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws -> UpdateHandoffJobDocument {
        switch job.state {
        case .queued:
            let claimed = try operations.launchClaimed(
                job,
                operations.makeId(),
                operations.now()
            )
            try persist(
                claimed,
                expectedRevision: job.revision,
                operations: operations
            )
            do {
                try operations.launchChildOwner(claimed)
            } catch {
                throw UpdateHandoffSupervisorWorkflowError.childLaunchFailed(
                    jobId: claimed.jobId,
                    launchId: claimed.launchId ?? "",
                    reason: operations.describeFailure(error)
                )
            }
            return claimed
        case .launching:
            return try reconcileLaunching(job, operations: operations)
        case .running:
            return try reconcileRunning(job, operations: operations)
        case .cancellationRequested:
            return try reconcileCancellation(job, operations: operations)
        case .succeeded, .failed, .interrupted:
            return job
        }
    }

    public func requestCancellation(
        _ job: UpdateHandoffJobDocument,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws -> UpdateHandoffJobDocument {
        let requested = try operations.cancellationRequested(
            job,
            operations.now()
        )
        try persist(
            requested,
            expectedRevision: job.revision,
            operations: operations
        )
        return requested
    }

    public func wait(
        jobId: String,
        attempts: Int,
        load: () throws -> UpdateHandoffJobDocument,
        pause: () -> Void
    ) throws -> UpdateHandoffJobDocument {
        precondition(attempts > 0)
        var last: UpdateHandoffJobDocument?
        for attempt in 0..<attempts {
            let loaded = try load()
            last = loaded
            if loaded.state.isTerminal {
                return loaded
            }
            if attempt + 1 < attempts {
                pause()
            }
        }
        throw UpdateHandoffSupervisorWorkflowError.waitTimedOut(
            jobId: jobId,
            state: last!.state
        )
    }

    private func reconcileLaunching(
        _ job: UpdateHandoffJobDocument,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws -> UpdateHandoffJobDocument {
        switch operations.readStartReceipt(job) {
        case .loaded(let receipt):
            let running = try operations.childStarted(
                job,
                receipt.child,
                operations.now()
            )
            try persist(
                running,
                expectedRevision: job.revision,
                operations: operations
            )
            return try reconcileRunning(running, operations: operations)
        case .missing:
            switch operations.readCompletionReceipt(job) {
            case .loaded(let receipt):
                let child = UpdateHandoffChildIdentity(
                    launchId: receipt.launchId,
                    processId: receipt.processId,
                    processGroupId: receipt.processGroupId,
                    startedAt: receipt.finishedAt
                )
                let running = try operations.childStarted(
                    job,
                    child,
                    operations.now()
                )
                try persist(
                    running,
                    expectedRevision: job.revision,
                    operations: operations
                )
                return try complete(
                    running,
                    receipt: receipt,
                    operations: operations
                )
            case .missing:
                do {
                    try operations.launchChildOwner(job)
                    return job
                } catch {
                    throw UpdateHandoffSupervisorWorkflowError
                        .childLaunchFailed(
                            jobId: job.jobId,
                            launchId: job.launchId ?? "",
                            reason: operations.describeFailure(error)
                        )
                }
            case .failed(let path, let reason):
                throw UpdateHandoffSupervisorWorkflowError
                    .completionReceiptReadFailed(
                        jobId: job.jobId,
                        path: path,
                        reason: reason
                    )
            }
        case .failed(let path, let reason):
            throw UpdateHandoffSupervisorWorkflowError.startReceiptReadFailed(
                jobId: job.jobId,
                path: path,
                reason: reason
            )
        }
    }

    private func reconcileRunning(
        _ job: UpdateHandoffJobDocument,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws -> UpdateHandoffJobDocument {
        switch operations.readCompletionReceipt(job) {
        case .loaded(let receipt):
            return try complete(job, receipt: receipt, operations: operations)
        case .missing:
            guard let child = job.child else {
                let interrupted = try operations.childCompletionUnavailable(
                    job,
                    "running job has no owned child identity",
                    operations.now()
                )
                try persist(
                    interrupted,
                    expectedRevision: job.revision,
                    operations: operations
                )
                return interrupted
            }
            switch operations.observeChild(child) {
            case .running:
                return job
            case .notRunning:
                let interrupted = try operations.childCompletionUnavailable(
                    job,
                    "owned child is not running and no completion receipt exists",
                    operations.now()
                )
                try persist(
                    interrupted,
                    expectedRevision: job.revision,
                    operations: operations
                )
                return interrupted
            case .failed(_, let reason):
                throw UpdateHandoffSupervisorWorkflowError
                    .childObservationFailed(jobId: job.jobId, reason: reason)
            }
        case .failed(let path, let reason):
            throw UpdateHandoffSupervisorWorkflowError
                .completionReceiptReadFailed(
                    jobId: job.jobId,
                    path: path,
                    reason: reason
                )
        }
    }

    private func reconcileCancellation(
        _ job: UpdateHandoffJobDocument,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws -> UpdateHandoffJobDocument {
        if let child = job.child {
            switch operations.terminateProcessTree(child) {
            case .terminated:
                break
            case .failed(_, let reason):
                throw UpdateHandoffSupervisorWorkflowError
                    .processTreeTerminationFailed(
                        jobId: job.jobId,
                        reason: reason
                    )
            }
        }
        let interrupted = try operations.processTreeTerminated(
            job,
            "cancellation requested by supervisor client",
            operations.now()
        )
        try persist(
            interrupted,
            expectedRevision: job.revision,
            operations: operations
        )
        return interrupted
    }

    private func complete(
        _ job: UpdateHandoffJobDocument,
        receipt: UpdateHandoffChildCompletionReceipt,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws -> UpdateHandoffJobDocument {
        let completed = try operations.childCompleted(
            job,
            receipt,
            operations.now()
        )
        try persist(
            completed,
            expectedRevision: job.revision,
            operations: operations
        )
        return completed
    }

    private func persist(
        _ job: UpdateHandoffJobDocument,
        expectedRevision: Int?,
        operations: UpdateHandoffSupervisorWorkflowOperations
    ) throws {
        do {
            try operations.save(job, expectedRevision)
        } catch {
            throw UpdateHandoffSupervisorWorkflowError.jobPersistenceFailed(
                jobId: job.jobId,
                expectedRevision: expectedRevision,
                reason: operations.describeFailure(error)
            )
        }
    }
}
