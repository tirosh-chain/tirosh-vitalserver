import Application
import Contracts
import Domain
import Foundation

public enum UpdateBootstrapCompletionEvidenceWorkflowError:
    Error,
    Equatable,
    Sendable
{
    case completionMissing(journalId: String)
}

public struct SettleRunningUpdateBootstrapWorkflowInput:
    Equatable,
    Sendable
{
    public let runningJournal: UpdateBootstrapJournal
    public let stagedRoot: URL

    public init(
        runningJournal: UpdateBootstrapJournal,
        stagedRoot: URL
    ) {
        self.runningJournal = runningJournal
        self.stagedRoot = stagedRoot
    }
}

public struct SettleRunningUpdateBootstrapWorkflowOperations {
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
    public let saveJournal: (UpdateBootstrapJournal, Int) throws -> Void
    public let makeInstalledRelease: (
        UpdateBootstrapJournal
    ) throws -> InstalledProductRelease
    public let settleSucceeded: (
        UpdateBootstrapJournal,
        InstalledProductRelease,
        Int,
        Int
    ) throws -> Void

    public init(
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
        saveJournal: @escaping (
            UpdateBootstrapJournal,
            Int
        ) throws -> Void,
        makeInstalledRelease: @escaping (
            UpdateBootstrapJournal
        ) throws -> InstalledProductRelease,
        settleSucceeded: @escaping (
            UpdateBootstrapJournal,
            InstalledProductRelease,
            Int,
            Int
        ) throws -> Void
    ) {
        self.readReceipt = readReceipt
        self.settle = settle
        self.readReport = readReport
        self.verifyReport = verifyReport
        self.saveJournal = saveJournal
        self.makeInstalledRelease = makeInstalledRelease
        self.settleSucceeded = settleSucceeded
    }
}

public struct SettleRunningUpdateBootstrapWorkflow {
    public init() {}

    public func run(
        input: SettleRunningUpdateBootstrapWorkflowInput,
        operations: SettleRunningUpdateBootstrapWorkflowOperations
    ) throws -> UpdateBootstrapJournal {
        let receiptURL = input.stagedRoot.appendingPathComponent(
            UpdateBootstrapHandoffPolicy.completionReceiptRelativePath
        )
        let settled = try operations.settle(
            input.runningJournal,
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
                input.runningJournal.journalRevision,
                release.installationRevision - 1
            )
        } else {
            try operations.saveJournal(
                settled,
                input.runningJournal.journalRevision
            )
        }
        return settled
    }
}
