import Contracts

public enum UpdateBootstrapJournalEvent: Equatable, Sendable {
    case verifiedAndStaged(
        updaterRelativePath: String,
        specificationRelativePath: String,
        observedAt: String
    )
    case handoffStarted(observedAt: String)
    case completed(UpdateBootstrapCompletionReceipt)
    case failed(reason: String, observedAt: String)
    case interrupted(reason: String, observedAt: String)
}

public enum UpdateBootstrapJournalTransitionError: Error, Equatable, Sendable {
    case invalidJournal(UpdateBootstrapJournalValidationError)
    case invalidCurrentState(
        state: UpdateBootstrapJournalState,
        event: String
    )
    case invalidRevision(expected: Int, actual: Int)
    case correlationMismatch(field: String, expected: String, actual: String)
    case invalidCompletionFailureReason
}

public enum UpdateBootstrapJournalStateMachine {
    public static func transition(
        journal: UpdateBootstrapJournal,
        event: UpdateBootstrapJournalEvent
    ) throws -> UpdateBootstrapJournal {
        do {
            try UpdateBootstrapJournalPolicy.validate(journal)
        } catch let error as UpdateBootstrapJournalValidationError {
            throw UpdateBootstrapJournalTransitionError.invalidJournal(error)
        }
        let result: UpdateBootstrapJournal
        switch event {
        case .verifiedAndStaged(
            let updaterRelativePath,
            let specificationRelativePath,
            let observedAt
        ):
            try requireState(journal, .admitted, event: "verified-and-staged")
            result = updated(
                journal,
                state: .handoffPending,
                stagedUpdaterRelativePath: updaterRelativePath,
                stagedSpecificationRelativePath: specificationRelativePath,
                completion: nil,
                failureReason: nil,
                observedAt: observedAt
            )
        case .handoffStarted(let observedAt):
            try requireState(journal, .handoffPending, event: "handoff-started")
            result = updated(
                journal,
                state: .running,
                stagedUpdaterRelativePath: journal.stagedUpdaterRelativePath,
                stagedSpecificationRelativePath: journal.stagedSpecificationRelativePath,
                completion: nil,
                failureReason: nil,
                observedAt: observedAt
            )
        case .completed(let receipt):
            try requireState(journal, .running, event: "completed")
            try validateCorrelation(journal: journal, receipt: receipt)
            let failureReason: String?
            switch receipt.outcome {
            case .succeeded:
                guard receipt.failureReason == nil else {
                    throw UpdateBootstrapJournalTransitionError
                        .invalidCompletionFailureReason
                }
                failureReason = nil
            case .failed:
                guard let reason = receipt.failureReason, !reason.isEmpty else {
                    throw UpdateBootstrapJournalTransitionError
                        .invalidCompletionFailureReason
                }
                failureReason = reason
            }
            result = updated(
                journal,
                state: receipt.outcome == .succeeded ? .succeeded : .failed,
                stagedUpdaterRelativePath: journal.stagedUpdaterRelativePath,
                stagedSpecificationRelativePath: journal.stagedSpecificationRelativePath,
                completion: receipt,
                failureReason: failureReason,
                observedAt: receipt.finishedAt
            )
        case .failed(let reason, let observedAt):
            guard [.admitted, .handoffPending, .running].contains(journal.state) else {
                throw UpdateBootstrapJournalTransitionError.invalidCurrentState(
                    state: journal.state,
                    event: "failed"
                )
            }
            result = updated(
                journal,
                state: .failed,
                stagedUpdaterRelativePath: journal.stagedUpdaterRelativePath,
                stagedSpecificationRelativePath: journal.stagedSpecificationRelativePath,
                completion: nil,
                failureReason: reason,
                observedAt: observedAt
            )
        case .interrupted(let reason, let observedAt):
            guard [.handoffPending, .running].contains(journal.state) else {
                throw UpdateBootstrapJournalTransitionError.invalidCurrentState(
                    state: journal.state,
                    event: "interrupted"
                )
            }
            result = updated(
                journal,
                state: .interrupted,
                stagedUpdaterRelativePath: journal.stagedUpdaterRelativePath,
                stagedSpecificationRelativePath: journal.stagedSpecificationRelativePath,
                completion: nil,
                failureReason: reason,
                observedAt: observedAt
            )
        }
        do {
            try UpdateBootstrapJournalPolicy.validate(result)
        } catch let error as UpdateBootstrapJournalValidationError {
            throw UpdateBootstrapJournalTransitionError.invalidJournal(error)
        }
        return result
    }

    private static func requireState(
        _ journal: UpdateBootstrapJournal,
        _ expected: UpdateBootstrapJournalState,
        event: String
    ) throws {
        guard journal.state == expected else {
            throw UpdateBootstrapJournalTransitionError.invalidCurrentState(
                state: journal.state,
                event: event
            )
        }
    }

    private static func validateCorrelation(
        journal: UpdateBootstrapJournal,
        receipt: UpdateBootstrapCompletionReceipt
    ) throws {
        guard receipt.expectedJournalRevision == journal.journalRevision else {
            throw UpdateBootstrapJournalTransitionError.invalidRevision(
                expected: journal.journalRevision,
                actual: receipt.expectedJournalRevision
            )
        }
        try requireEqual(
            field: "updateId",
            expected: journal.id,
            actual: receipt.updateId
        )
        try requireEqual(
            field: "requestId",
            expected: journal.requestId,
            actual: receipt.requestId
        )
        try requireEqual(
            field: "bootstrapEnvelopeId",
            expected: journal.envelope.id,
            actual: receipt.bootstrapEnvelopeId
        )
        try requireEqual(
            field: "updateSpecificationSHA256",
            expected: journal.envelope.specification.sha256,
            actual: receipt.updateSpecificationSHA256
        )
    }

    private static func requireEqual(
        field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw UpdateBootstrapJournalTransitionError.correlationMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }

    private static func updated(
        _ journal: UpdateBootstrapJournal,
        state: UpdateBootstrapJournalState,
        stagedUpdaterRelativePath: String?,
        stagedSpecificationRelativePath: String?,
        completion: UpdateBootstrapCompletionReceipt?,
        failureReason: String?,
        observedAt: String
    ) -> UpdateBootstrapJournal {
        UpdateBootstrapJournal(
            schemaVersion: journal.schemaVersion,
            id: journal.id,
            journalRevision: journal.journalRevision + 1,
            operationId: journal.operationId,
            targetInstallationId: journal.targetInstallationId,
            expectedInstallationRevision: journal.expectedInstallationRevision,
            requestId: journal.requestId,
            envelope: journal.envelope,
            bootstrapSignedSHA256: journal.bootstrapSignedSHA256,
            state: state,
            stagedUpdaterRelativePath: stagedUpdaterRelativePath,
            stagedSpecificationRelativePath: stagedSpecificationRelativePath,
            completion: completion,
            failureReason: failureReason,
            createdAt: journal.createdAt,
            updatedAt: observedAt,
            platformAgentSelectionCorrelation:
                journal.platformAgentSelectionCorrelation
        )
    }
}
