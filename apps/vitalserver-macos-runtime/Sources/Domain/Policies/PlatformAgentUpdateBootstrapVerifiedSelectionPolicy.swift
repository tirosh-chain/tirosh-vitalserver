import Contracts

public enum PlatformAgentUpdateBootstrapVerifiedSelectionValidationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSchemaVersion(String)
    case unexpectedProducer(String)
    case invalidSelectionId(String)
    case invalidVerificationInvocationId(String)
    case invalidUpdateId(String)
    case invalidCanonicalPayloadSHA256(String)
    case invalidObservedBundlePath(String)
    case invalidObservedAt(String)
    case unsupportedState(String)
    case unexpectedField(String)
    case missingField(String)
    case invalidBoundRequestId(String)
}

public enum PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError:
    Error,
    Equatable,
    Sendable
{
    case invalidSelection(PlatformAgentUpdateBootstrapVerifiedSelectionValidationError)
    case stale
    case conflict(expectedPath: String, actualPath: String)
    case invalidRequestId(String)
    case inFlight(requestId: String)
    case invalidCurrentState(state: String, event: String)
    case requestMismatch(expected: String, actual: String)
}

public enum PlatformAgentUpdateBootstrapApplySelectionProofPolicyError:
    Error,
    Equatable,
    Sendable
{
    case missing
    case invalid(PlatformAgentUpdateBootstrapVerifiedSelectionValidationError)
    case identityMismatch(field: String, expected: String, actual: String)
}

public enum PlatformAgentUpdateBootstrapVerifiedSelectionPolicy {
    public static func verified(
        selectionId: String,
        verificationInvocationId: String,
        updateId: String,
        canonicalPayloadSHA256: String,
        observedBundlePath: String,
        observedAt: String
    ) -> PlatformAgentUpdateBootstrapVerifiedSelection {
        PlatformAgentUpdateBootstrapVerifiedSelection(
            schemaVersion:
                PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .schemaVersion,
            producer: PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .producer,
            selectionId: selectionId,
            verificationInvocationId: verificationInvocationId,
            updateId: updateId,
            canonicalPayloadSHA256: canonicalPayloadSHA256,
            observedBundlePath: observedBundlePath,
            state: PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .stateVerified,
            observedAt: observedAt
        )
    }

    public static func validate(
        _ selection: PlatformAgentUpdateBootstrapVerifiedSelection
    ) throws {
        guard selection.schemaVersion
            == PlatformAgentUpdateBootstrapVerifiedSelectionContract
            .schemaVersion
        else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .unsupportedSchemaVersion(selection.schemaVersion)
        }
        guard selection.producer
            == PlatformAgentUpdateBootstrapVerifiedSelectionContract.producer
        else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .unexpectedProducer(selection.producer)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(selection.selectionId)
        else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidSelectionId(selection.selectionId)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(
            selection.verificationInvocationId
        ) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidVerificationInvocationId(
                    selection.verificationInvocationId
                )
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(selection.updateId)
        else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidUpdateId(selection.updateId)
        }
        guard isSHA256(selection.canonicalPayloadSHA256) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidCanonicalPayloadSHA256(
                    selection.canonicalPayloadSHA256
                )
        }
        guard isAbsolutePath(selection.observedBundlePath) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidObservedBundlePath(selection.observedBundlePath)
        }
        guard UpdateBootstrapCanonicalTimestampSyntax.isCanonical(
            selection.observedAt
        ) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidObservedAt(selection.observedAt)
        }
        switch selection.state {
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateVerified:
            guard selection.boundRequestId == nil else {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                    .unexpectedField("boundRequestId")
            }
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract
            .stateApplyCommitted,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateSpent:
            guard let requestId = selection.boundRequestId else {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                    .missingField("boundRequestId")
            }
            guard UpdateBootstrapIdentifierSyntax.isIdentifier(requestId) else {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                    .invalidBoundRequestId(requestId)
            }
        default:
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .unsupportedState(selection.state)
        }
    }

    public static func replace(
        current: PlatformAgentUpdateBootstrapVerifiedSelection?,
        with next: PlatformAgentUpdateBootstrapVerifiedSelection
    ) throws -> PlatformAgentUpdateBootstrapVerifiedSelection {
        do {
            try validate(next)
        } catch let error as
            PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
        {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidSelection(error)
        }
        guard next.state
            == PlatformAgentUpdateBootstrapVerifiedSelectionContract
            .stateVerified
        else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidCurrentState(state: next.state, event: "record")
        }
        if let current {
            do {
                try validate(current)
            } catch let error as
                PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
            {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                    .invalidSelection(error)
            }
            if current.state
                == PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .stateApplyCommitted
            {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                    .inFlight(requestId: current.boundRequestId ?? "")
            }
        }
        return next
    }

    public static func commitApply(
        selection: PlatformAgentUpdateBootstrapVerifiedSelection,
        requestId: String,
        observedBundlePath: String,
        observedAt: String
    ) throws -> (
        selection: PlatformAgentUpdateBootstrapVerifiedSelection,
        persisted: Bool
    ) {
        do {
            try validate(selection)
        } catch let error as
            PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
        {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidSelection(error)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(requestId) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidRequestId(requestId)
        }
        switch selection.state {
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateVerified:
            guard selection.observedBundlePath == observedBundlePath else {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                    .conflict(
                        expectedPath: selection.observedBundlePath,
                        actualPath: observedBundlePath
                    )
            }
            let committed = PlatformAgentUpdateBootstrapVerifiedSelection(
                schemaVersion: selection.schemaVersion,
                producer: selection.producer,
                selectionId: selection.selectionId,
                verificationInvocationId: selection.verificationInvocationId,
                updateId: selection.updateId,
                canonicalPayloadSHA256: selection.canonicalPayloadSHA256,
                observedBundlePath: selection.observedBundlePath,
                state: PlatformAgentUpdateBootstrapVerifiedSelectionContract
                    .stateApplyCommitted,
                boundRequestId: requestId,
                observedAt: observedAt
            )
            try validate(committed)
            return (committed, true)
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract
            .stateApplyCommitted:
            guard selection.boundRequestId == requestId else {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                    .stale
            }
            return (selection, false)
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateSpent:
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .stale
        default:
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidCurrentState(
                    state: selection.state,
                    event: "commitApply"
                )
        }
    }

    public static func spend(
        selection: PlatformAgentUpdateBootstrapVerifiedSelection,
        requestId: String,
        observedAt: String
    ) throws -> (
        selection: PlatformAgentUpdateBootstrapVerifiedSelection,
        persisted: Bool
    ) {
        do {
            try validate(selection)
        } catch let error as
            PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
        {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidSelection(error)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(requestId) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidRequestId(requestId)
        }
        switch selection.state {
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract
            .stateApplyCommitted:
            guard let bound = selection.boundRequestId, bound == requestId else {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                    .requestMismatch(
                        expected: selection.boundRequestId ?? "",
                        actual: requestId
                    )
            }
            let spent = PlatformAgentUpdateBootstrapVerifiedSelection(
                schemaVersion: selection.schemaVersion,
                producer: selection.producer,
                selectionId: selection.selectionId,
                verificationInvocationId: selection.verificationInvocationId,
                updateId: selection.updateId,
                canonicalPayloadSHA256: selection.canonicalPayloadSHA256,
                observedBundlePath: selection.observedBundlePath,
                state: PlatformAgentUpdateBootstrapVerifiedSelectionContract
                    .stateSpent,
                boundRequestId: bound,
                observedAt: observedAt
            )
            try validate(spent)
            return (spent, true)
        case PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateSpent:
            guard selection.boundRequestId == requestId else {
                throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                    .requestMismatch(
                        expected: selection.boundRequestId ?? "",
                        actual: requestId
                    )
            }
            return (selection, false)
        default:
            throw PlatformAgentUpdateBootstrapVerifiedSelectionTransitionError
                .invalidCurrentState(state: selection.state, event: "spend")
        }
    }

    public static func validateJournalCorrelation(
        _ correlation: UpdateBootstrapPlatformAgentSelectionCorrelation
    ) throws {
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(
            correlation.selectionId
        ) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidSelectionId(correlation.selectionId)
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(
            correlation.verificationInvocationId
        ) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidVerificationInvocationId(
                    correlation.verificationInvocationId
                )
        }
        guard UpdateBootstrapIdentifierSyntax.isIdentifier(correlation.updateId)
        else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidUpdateId(correlation.updateId)
        }
        guard isSHA256(correlation.canonicalPayloadSHA256) else {
            throw PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                .invalidCanonicalPayloadSHA256(
                    correlation.canonicalPayloadSHA256
                )
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func isAbsolutePath(_ value: String) -> Bool {
        !value.isEmpty && value.hasPrefix("/") && !value.contains("\0")
    }
}

public enum PlatformAgentUpdateBootstrapApplySelectionProofPolicy {
    public static func prove(
        journalCorrelation: UpdateBootstrapPlatformAgentSelectionCorrelation?,
        expectedVerificationInvocationId: String,
        expectedUpdateId: String,
        expectedCanonicalPayloadSHA256: String
    ) throws -> UpdateBootstrapPlatformAgentSelectionCorrelation {
        guard let correlation = journalCorrelation else {
            throw PlatformAgentUpdateBootstrapApplySelectionProofPolicyError
                .missing
        }
        do {
            try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
                .validateJournalCorrelation(correlation)
        } catch let error as
            PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
        {
            throw PlatformAgentUpdateBootstrapApplySelectionProofPolicyError
                .invalid(error)
        }
        try requireEqual(
            field: "verificationInvocationId",
            expected: expectedVerificationInvocationId,
            actual: correlation.verificationInvocationId
        )
        try requireEqual(
            field: "updateId",
            expected: expectedUpdateId,
            actual: correlation.updateId
        )
        try requireEqual(
            field: "canonicalPayloadSHA256",
            expected: expectedCanonicalPayloadSHA256,
            actual: correlation.canonicalPayloadSHA256
        )
        return correlation
    }

    private static func requireEqual(
        field: String,
        expected: String,
        actual: String
    ) throws {
        guard expected == actual else {
            throw PlatformAgentUpdateBootstrapApplySelectionProofPolicyError
                .identityMismatch(
                    field: field,
                    expected: expected,
                    actual: actual
                )
        }
    }
}
