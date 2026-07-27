import Application
import Contracts
import Foundation

public struct UpdateBootstrapHandoffWorkflowInput: Equatable, Sendable {
    public let admittedJournal: UpdateBootstrapJournal
    public let verification: VerifiedUpdateBootstrapClosure
    public let staging: UpdateBootstrapStagingInput

    public init(
        admittedJournal: UpdateBootstrapJournal,
        verification: VerifiedUpdateBootstrapClosure,
        staging: UpdateBootstrapStagingInput
    ) {
        self.admittedJournal = admittedJournal
        self.verification = verification
        self.staging = staging
    }
}

public struct UpdateBootstrapHandoffWorkflowOutput: Equatable, Sendable {
    public let journal: UpdateBootstrapJournal
    public let updaterExitCode: Int32

    public init(journal: UpdateBootstrapJournal, updaterExitCode: Int32) {
        self.journal = journal
        self.updaterExitCode = updaterExitCode
    }
}

public enum UpdateBootstrapHandoffWorkflowError: Error, Equatable, Sendable {
    case journalPersistenceFailed(
        state: UpdateBootstrapJournalState,
        reason: String
    )
    case operationFailed(reason: String)
    case operationAndFailureTransitionFailed(
        operationReason: String,
        transitionReason: String
    )
    case operationAndFailurePersistenceFailed(
        operationReason: String,
        persistenceReason: String
    )
}

public struct UpdateBootstrapHandoffWorkflowOperations {
    public let saveJournal: (UpdateBootstrapJournal, Int?) throws -> Void
    public let stage: (
        UpdateBootstrapStagingInput
    ) throws -> StagedUpdateBootstrapBundle
    public let verifiedAndStaged: (
        UpdateBootstrapJournal,
        VerifiedUpdateBootstrapClosure,
        String,
        String,
        String
    ) throws -> UpdateBootstrapJournal
    public let handoffStarted: (
        UpdateBootstrapJournal,
        String
    ) throws -> UpdateBootstrapJournal
    public let makeInvocation: (
        UpdateBootstrapJournal
    ) throws -> UpdateBootstrapHandoffInvocation
    public let writeInvocation: (
        UpdateBootstrapHandoffInvocation,
        URL
    ) throws -> WrittenUpdateBootstrapHandoffInvocation
    public let launch: (
        UpdateBootstrapHandoffInvocation,
        URL,
        URL
    ) throws -> RuntimeProcessResult
    public let readReceipt: (
        URL
    ) -> UpdateBootstrapCompletionReceiptReadResult
    public let settle: (
        UpdateBootstrapJournal,
        UpdateBootstrapCompletionReceiptReadResult
    ) throws -> UpdateBootstrapJournal
    public let fail: (
        UpdateBootstrapJournal,
        String,
        String
    ) throws -> UpdateBootstrapJournal
    public let now: () -> String
    public let describeFailure: (Error) -> String

    public init(
        saveJournal: @escaping (UpdateBootstrapJournal, Int?) throws -> Void,
        stage: @escaping (
            UpdateBootstrapStagingInput
        ) throws -> StagedUpdateBootstrapBundle,
        verifiedAndStaged: @escaping (
            UpdateBootstrapJournal,
            VerifiedUpdateBootstrapClosure,
            String,
            String,
            String
        ) throws -> UpdateBootstrapJournal,
        handoffStarted: @escaping (
            UpdateBootstrapJournal,
            String
        ) throws -> UpdateBootstrapJournal,
        makeInvocation: @escaping (
            UpdateBootstrapJournal
        ) throws -> UpdateBootstrapHandoffInvocation,
        writeInvocation: @escaping (
            UpdateBootstrapHandoffInvocation,
            URL
        ) throws -> WrittenUpdateBootstrapHandoffInvocation,
        launch: @escaping (
            UpdateBootstrapHandoffInvocation,
            URL,
            URL
        ) throws -> RuntimeProcessResult,
        readReceipt: @escaping (
            URL
        ) -> UpdateBootstrapCompletionReceiptReadResult,
        settle: @escaping (
            UpdateBootstrapJournal,
            UpdateBootstrapCompletionReceiptReadResult
        ) throws -> UpdateBootstrapJournal,
        fail: @escaping (
            UpdateBootstrapJournal,
            String,
            String
        ) throws -> UpdateBootstrapJournal,
        now: @escaping () -> String,
        describeFailure: @escaping (Error) -> String
    ) {
        self.saveJournal = saveJournal
        self.stage = stage
        self.verifiedAndStaged = verifiedAndStaged
        self.handoffStarted = handoffStarted
        self.makeInvocation = makeInvocation
        self.writeInvocation = writeInvocation
        self.launch = launch
        self.readReceipt = readReceipt
        self.settle = settle
        self.fail = fail
        self.now = now
        self.describeFailure = describeFailure
    }
}

public struct UpdateBootstrapHandoffWorkflow {
    public init() {}

    public func run(
        input: UpdateBootstrapHandoffWorkflowInput,
        operations: UpdateBootstrapHandoffWorkflowOperations
    ) throws -> UpdateBootstrapHandoffWorkflowOutput {
        try save(
            input.admittedJournal,
            expectedRevision: nil,
            operations: operations
        )

        let staged: StagedUpdateBootstrapBundle
        do {
            staged = try operations.stage(input.staging)
        } catch {
            throw failureAfterPersistedState(
                journal: input.admittedJournal,
                operationError: error,
                operations: operations
            )
        }

        let pending: UpdateBootstrapJournal
        do {
            pending = try operations.verifiedAndStaged(
                input.admittedJournal,
                input.verification,
                input.admittedJournal.envelope.nextUpdaterArtifact.relativePath,
                input.admittedJournal.envelope.specification.relativePath,
                operations.now()
            )
        } catch {
            throw failureAfterPersistedState(
                journal: input.admittedJournal,
                operationError: error,
                operations: operations
            )
        }
        try save(
            pending,
            expectedRevision: input.admittedJournal.journalRevision,
            operations: operations
        )

        let running: UpdateBootstrapJournal
        do {
            running = try operations.handoffStarted(pending, operations.now())
        } catch {
            throw failureAfterPersistedState(
                journal: pending,
                operationError: error,
                operations: operations
            )
        }
        try save(
            running,
            expectedRevision: pending.journalRevision,
            operations: operations
        )

        do {
            let invocation = try operations.makeInvocation(running)
            let written = try operations.writeInvocation(
                invocation,
                staged.root
            )
            let process = try operations.launch(
                invocation,
                written.url,
                staged.root
            )
            let receiptURL = staged.root.appendingPathComponent(
                invocation.completionReceiptRelativePath
            )
            let settled = try operations.settle(
                running,
                operations.readReceipt(receiptURL)
            )
            try save(
                settled,
                expectedRevision: running.journalRevision,
                operations: operations
            )
            return UpdateBootstrapHandoffWorkflowOutput(
                journal: settled,
                updaterExitCode: process.exitCode
            )
        } catch {
            throw failureAfterPersistedState(
                journal: running,
                operationError: error,
                operations: operations
            )
        }
    }

    private func save(
        _ journal: UpdateBootstrapJournal,
        expectedRevision: Int?,
        operations: UpdateBootstrapHandoffWorkflowOperations
    ) throws {
        do {
            try operations.saveJournal(journal, expectedRevision)
        } catch {
            throw UpdateBootstrapHandoffWorkflowError.journalPersistenceFailed(
                state: journal.state,
                reason: operations.describeFailure(error)
            )
        }
    }

    private func failureAfterPersistedState(
        journal: UpdateBootstrapJournal,
        operationError: Error,
        operations: UpdateBootstrapHandoffWorkflowOperations
    ) -> UpdateBootstrapHandoffWorkflowError {
        let operationReason = operations.describeFailure(operationError)
        let failed: UpdateBootstrapJournal
        do {
            failed = try operations.fail(
                journal,
                operationReason,
                operations.now()
            )
        } catch {
            return .operationAndFailureTransitionFailed(
                operationReason: operationReason,
                transitionReason: operations.describeFailure(error)
            )
        }
        do {
            try operations.saveJournal(failed, journal.journalRevision)
            return .operationFailed(reason: operationReason)
        } catch {
            return .operationAndFailurePersistenceFailed(
                operationReason: operationReason,
                persistenceReason: operations.describeFailure(error)
            )
        }
    }
}
