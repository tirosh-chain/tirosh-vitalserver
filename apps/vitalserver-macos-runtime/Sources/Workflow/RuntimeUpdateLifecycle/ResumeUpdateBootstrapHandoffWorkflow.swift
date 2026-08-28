import Application
import Contracts
import Foundation

public struct ResumeUpdateBootstrapHandoffWorkflowInput:
    Equatable,
    Sendable
{
    public let pendingJournal: UpdateBootstrapJournal
    public let stagedRoot: URL

    public init(
        pendingJournal: UpdateBootstrapJournal,
        stagedRoot: URL
    ) {
        self.pendingJournal = pendingJournal
        self.stagedRoot = stagedRoot
    }
}

public enum ResumeUpdateBootstrapHandoffWorkflowError:
    Error,
    Equatable,
    Sendable
{
    case runningJournalPersistenceFailed(reason: String)
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

public struct ResumeUpdateBootstrapHandoffWorkflowOperations {
    public let saveJournal: (UpdateBootstrapJournal, Int) throws -> Void
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
    public let readReport: (
        String,
        URL
    ) -> UpdateBootstrapCompletionReportReadResult
    public let verifyReport: (
        UpdateBootstrapJournal,
        UpdateBootstrapCompletionReportReadResult
    ) throws -> Void
    public let makeInstalledRelease: (
        UpdateBootstrapJournal
    ) throws -> InstalledProductRelease
    public let settleSucceeded: (
        UpdateBootstrapJournal,
        InstalledProductRelease,
        Int,
        Int
    ) throws -> Void
    public let fail: (
        UpdateBootstrapJournal,
        String,
        String
    ) throws -> UpdateBootstrapJournal
    public let now: () -> String
    public let describeFailure: (Error) -> String

    public init(
        saveJournal: @escaping (UpdateBootstrapJournal, Int) throws -> Void,
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
        readReport: @escaping (
            String,
            URL
        ) -> UpdateBootstrapCompletionReportReadResult,
        verifyReport: @escaping (
            UpdateBootstrapJournal,
            UpdateBootstrapCompletionReportReadResult
        ) throws -> Void,
        makeInstalledRelease: @escaping (
            UpdateBootstrapJournal
        ) throws -> InstalledProductRelease,
        settleSucceeded: @escaping (
            UpdateBootstrapJournal,
            InstalledProductRelease,
            Int,
            Int
        ) throws -> Void,
        fail: @escaping (
            UpdateBootstrapJournal,
            String,
            String
        ) throws -> UpdateBootstrapJournal,
        now: @escaping () -> String,
        describeFailure: @escaping (Error) -> String
    ) {
        self.saveJournal = saveJournal
        self.handoffStarted = handoffStarted
        self.makeInvocation = makeInvocation
        self.writeInvocation = writeInvocation
        self.launch = launch
        self.readReceipt = readReceipt
        self.settle = settle
        self.readReport = readReport
        self.verifyReport = verifyReport
        self.makeInstalledRelease = makeInstalledRelease
        self.settleSucceeded = settleSucceeded
        self.fail = fail
        self.now = now
        self.describeFailure = describeFailure
    }
}

public struct ResumeUpdateBootstrapHandoffWorkflow {
    public init() {}

    public func run(
        input: ResumeUpdateBootstrapHandoffWorkflowInput,
        operations: ResumeUpdateBootstrapHandoffWorkflowOperations
    ) throws -> UpdateBootstrapHandoffWorkflowOutput {
        let running = try operations.handoffStarted(
            input.pendingJournal,
            operations.now()
        )
        do {
            try operations.saveJournal(
                running,
                input.pendingJournal.journalRevision
            )
        } catch {
            throw ResumeUpdateBootstrapHandoffWorkflowError
                .runningJournalPersistenceFailed(
                    reason: operations.describeFailure(error)
                )
        }

        do {
            let invocation = try operations.makeInvocation(running)
            let written = try operations.writeInvocation(
                invocation,
                input.stagedRoot
            )
            let process = try operations.launch(
                invocation,
                written.url,
                input.stagedRoot
            )
            let receiptURL = input.stagedRoot.appendingPathComponent(
                invocation.completionReceiptRelativePath
            )
            let settled = try operations.settle(
                running,
                operations.readReceipt(receiptURL)
            )
            guard let completion = settled.completion else {
                throw UpdateBootstrapCompletionEvidenceWorkflowError
                    .completionMissing(journalId: settled.id)
            }
            try operations.verifyReport(
                settled,
                operations.readReport(
                    completion.reportRelativePath,
                    input.stagedRoot
                )
            )
            if settled.state == .succeeded {
                let release = try operations.makeInstalledRelease(settled)
                try operations.settleSucceeded(
                    settled,
                    release,
                    running.journalRevision,
                    release.installationRevision - 1
                )
            } else {
                try operations.saveJournal(
                    settled,
                    running.journalRevision
                )
            }
            return UpdateBootstrapHandoffWorkflowOutput(
                journal: settled,
                updaterExitCode: process.exitCode
            )
        } catch {
            throw failureAfterRunningState(
                running,
                operationError: error,
                operations: operations
            )
        }
    }

    private func failureAfterRunningState(
        _ journal: UpdateBootstrapJournal,
        operationError: Error,
        operations: ResumeUpdateBootstrapHandoffWorkflowOperations
    ) -> ResumeUpdateBootstrapHandoffWorkflowError {
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
            try operations.saveJournal(
                failed,
                journal.journalRevision
            )
            return .operationFailed(reason: operationReason)
        } catch {
            return .operationAndFailurePersistenceFailed(
                operationReason: operationReason,
                persistenceReason: operations.describeFailure(error)
            )
        }
    }
}
