import Contracts
import Domain

public enum UpdateBootstrapLifecycleProofExpectation:
    String,
    Equatable,
    Sendable
{
    case succeeded
    case failedRolledBack = "failed-rolled-back"
}

public enum ProveUpdateBootstrapLifecycleError:
    Error,
    Equatable,
    Sendable
{
    case journalMissing(id: String)
    case journalReadFailed(id: String, reason: String)
    case journalIdentityMismatch(expected: String, actual: String)
    case completionMissing(id: String)
    case reportCorrelationMismatch
    case terminalJournalWaitTimedOut(
        id: String,
        timeoutMilliseconds: UInt64,
        lastState: UpdateBootstrapJournalState
    )
    case hostFailureRollbackEvidenceInvalid(
        applyLayers: [UpdateLayer],
        rollbackLayers: [UpdateLayer]
    )
    case expectedSuccess(
        journalState: UpdateBootstrapJournalState,
        completionOutcome: UpdateBootstrapCompletionOutcome,
        reportState: ProductUpdateExecutionState
    )
    case expectedFailedRollback(
        journalState: UpdateBootstrapJournalState,
        completionOutcome: UpdateBootstrapCompletionOutcome,
        reportState: ProductUpdateExecutionState,
        rollbackState: ProductUpdateRollbackState
    )
    case guestControlBaseURLInvalid(String)
    case guestControlBaseURLHostLoopback(String)
    case guestAddressMissing(String)
    case guestAddressInvalid(String)
    case guestAddressStale(String)
    case guestAddressReadFailed(String)
    case guestAddressNotReported
    case guestControlHostMismatch(
        invocationHost: String,
        observedAddress: String
    )
    case guestControlPortMismatch(actual: Int?, expected: Int)
    case hostPlatformLayerMissing
    case hostPlatformOperationMissing(id: String)
    case hostPlatformOperationReadFailed(id: String, reason: String)
    case hostPlatformIdentityMismatch(
        field: String,
        expected: String,
        actual: String
    )
    case hostPlatformPhaseMismatch(
        accepted: [HostPlatformInstallationPhase],
        actual: HostPlatformInstallationPhase
    )
    case hostPlatformInstallationMissing
    case hostPlatformInstallationReadFailed(reason: String)
    case hostPlatformInstallationIdentityMismatch(
        field: String,
        expected: String,
        actual: String
    )
}

public struct ProveUpdateBootstrapLifecycleUseCase {
    public init() {}

    public func execute(
        expectation: UpdateBootstrapLifecycleProofExpectation,
        journal: UpdateBootstrapJournal,
        report: ProductUpdateExecutionReport
    ) throws -> UpdateBootstrapJournal {
        guard let completion = journal.completion else {
            throw ProveUpdateBootstrapLifecycleError.completionMissing(
                id: journal.id
            )
        }
        guard report.updateId == journal.id,
              report.requestId == journal.requestId,
              report.bootstrapEnvelopeId == journal.envelope.id,
              report.updateSpecificationSHA256
                == journal.envelope.specification.sha256 else {
            throw ProveUpdateBootstrapLifecycleError
                .reportCorrelationMismatch
        }

        switch expectation {
        case .succeeded:
            guard journal.state == .succeeded,
                  completion.outcome == .succeeded,
                  report.state == .succeeded else {
                throw ProveUpdateBootstrapLifecycleError.expectedSuccess(
                    journalState: journal.state,
                    completionOutcome: completion.outcome,
                    reportState: report.state
                )
            }
        case .failedRolledBack:
            guard journal.state == .failed,
                  completion.outcome == .failed,
                  report.state == .failed,
                  report.rollback.state == .succeeded else {
                throw ProveUpdateBootstrapLifecycleError
                    .expectedFailedRollback(
                        journalState: journal.state,
                        completionOutcome: completion.outcome,
                        reportState: report.state,
                        rollbackState: report.rollback.state
                    )
            }
            let expectedApplyLayers: [UpdateLayer] = [
                .container,
                .guestRuntime,
                .hostPlatform,
            ]
            let expectedRollbackLayers: [UpdateLayer] = [
                .guestRuntime,
                .container,
            ]
            guard report.applyReceipts.map(\.layer) == expectedApplyLayers,
                  report.applyReceipts.map(\.operation).allSatisfy({
                      $0 == .apply
                  }),
                  report.applyReceipts.dropLast().allSatisfy({
                      $0.state == .succeeded
                  }),
                  report.applyReceipts.last?.state == .failed,
                  report.rollbackReceipts.map(\.layer)
                    == expectedRollbackLayers,
                  report.rollbackReceipts.map(\.operation).allSatisfy({
                      $0 == .rollback
                  }),
                  report.rollbackReceipts.allSatisfy({
                      $0.state == .succeeded
                  }) else {
                throw ProveUpdateBootstrapLifecycleError
                    .hostFailureRollbackEvidenceInvalid(
                        applyLayers: report.applyReceipts.map(\.layer),
                        rollbackLayers:
                            report.rollbackReceipts.map(\.layer)
                    )
            }
        }
        return journal
    }

    public func proveGuestControl(
        invocation: UpdateBootstrapHandoffInvocation,
        guestAddressRead: RuntimeGuestAddressReadResult
    ) throws {
        do {
            try UpdateBootstrapGuestControlProofPolicy.prove(
                persistedGuestControlBaseURL: invocation.guestControlBaseURL,
                guestAddressRead: guestAddressRead,
                expectedPort: RuntimeGuestControlEndpointContract.port
            )
        } catch let error as UpdateBootstrapGuestControlProofPolicyError {
            throw mapGuestControl(error)
        }
    }

    public func proveHostPlatform(
        expectation: UpdateBootstrapLifecycleProofExpectation,
        updateId: String,
        apply: HostPlatformLayerTransition,
        applyArtifactSHA256: String,
        operationRead: HostPlatformInstallationOperationReadResult,
        installationRead: HostPlatformInstallationManifestReadResult
    ) throws -> HostPlatformInstallationOperation {
        let operationId = HostPlatformUpdateProofPolicy
            .expectedApplyOperationId(updateId: updateId)
        let operation: HostPlatformInstallationOperation
        switch operationRead {
        case .missing:
            throw ProveUpdateBootstrapLifecycleError
                .hostPlatformOperationMissing(id: operationId)
        case .failed(let reason):
            throw ProveUpdateBootstrapLifecycleError
                .hostPlatformOperationReadFailed(
                    id: operationId,
                    reason: reason
                )
        case .loaded(let loaded):
            operation = loaded
        }

        let installation: HostPlatformInstallationManifest
        switch installationRead {
        case .missing:
            throw ProveUpdateBootstrapLifecycleError
                .hostPlatformInstallationMissing
        case .failed(let reason):
            throw ProveUpdateBootstrapLifecycleError
                .hostPlatformInstallationReadFailed(reason: reason)
        case .loaded(let loaded):
            installation = loaded
        }

        do {
            try HostPlatformUpdateProofPolicy.prove(
                acceptedPhases: hostPlatformAcceptedPhases(expectation),
                updateId: updateId,
                apply: apply,
                applyArtifactSHA256: applyArtifactSHA256,
                operation: operation,
                installation: installation
            )
        } catch let error as HostPlatformUpdateProofPolicyError {
            throw mapHostPlatform(error)
        }
        return operation
    }

    public func requireHostPlatformLayer(
        specification: ProductUpdateSpecification
    ) throws -> ProductUpdateLayerPlan {
        let layers = specification.layerPlan.filter { $0.layer == .hostPlatform }
        guard layers.count == 1, let layer = layers.first else {
            throw ProveUpdateBootstrapLifecycleError.hostPlatformLayerMissing
        }
        return layer
    }

    public func awaitTerminalJournal(
        updateId: String,
        timeoutMilliseconds: UInt64,
        pollIntervalMilliseconds: UInt64,
        elapsedMilliseconds: () -> UInt64,
        wait: (UInt64) -> Void,
        readJournal: () -> UpdateBootstrapJournalReadResult
    ) throws -> UpdateBootstrapJournal {
        precondition(timeoutMilliseconds > 0)
        precondition(pollIntervalMilliseconds > 0)

        while true {
            let journal = try requireJournal(
                updateId: updateId,
                journalRead: readJournal()
            )
            if journal.state == .succeeded || journal.state == .failed {
                return journal
            }

            let elapsed = elapsedMilliseconds()
            guard elapsed < timeoutMilliseconds else {
                throw ProveUpdateBootstrapLifecycleError
                    .terminalJournalWaitTimedOut(
                        id: updateId,
                        timeoutMilliseconds: timeoutMilliseconds,
                        lastState: journal.state
                    )
            }
            wait(
                min(
                    pollIntervalMilliseconds,
                    timeoutMilliseconds - elapsed
                )
            )
        }
    }

    public func requireJournal(
        updateId: String,
        journalRead: UpdateBootstrapJournalReadResult
    ) throws -> UpdateBootstrapJournal {
        let journal: UpdateBootstrapJournal
        switch journalRead {
        case .missing:
            throw ProveUpdateBootstrapLifecycleError.journalMissing(
                id: updateId
            )
        case .failed(let reason):
            throw ProveUpdateBootstrapLifecycleError.journalReadFailed(
                id: updateId,
                reason: reason
            )
        case .loaded(let loaded):
            journal = loaded
        }
        guard journal.id == updateId else {
            throw ProveUpdateBootstrapLifecycleError
                .journalIdentityMismatch(
                    expected: updateId,
                    actual: journal.id
                )
        }
        return journal
    }

    private func hostPlatformAcceptedPhases(
        _ expectation: UpdateBootstrapLifecycleProofExpectation
    ) -> [HostPlatformInstallationPhase] {
        switch expectation {
        case .succeeded:
            return [.completed]
        case .failedRolledBack:
            return [.failed, .compensated]
        }
    }

    private func mapGuestControl(
        _ error: UpdateBootstrapGuestControlProofPolicyError
    ) -> ProveUpdateBootstrapLifecycleError {
        switch error {
        case .invalidURL(let url):
            return .guestControlBaseURLInvalid(url)
        case .hostLoopback(let url):
            return .guestControlBaseURLHostLoopback(url)
        case .guestAddressMissing(let reason):
            return .guestAddressMissing(reason)
        case .guestAddressInvalid(let reason):
            return .guestAddressInvalid(reason)
        case .guestAddressStale(let reason):
            return .guestAddressStale(reason)
        case .guestAddressReadFailed(let reason):
            return .guestAddressReadFailed(reason)
        case .guestAddressNotReported:
            return .guestAddressNotReported
        case .hostMismatch(let invocationHost, let observedAddress):
            return .guestControlHostMismatch(
                invocationHost: invocationHost,
                observedAddress: observedAddress
            )
        case .portMismatch(let actual, let expected):
            return .guestControlPortMismatch(actual: actual, expected: expected)
        }
    }

    private func mapHostPlatform(
        _ error: HostPlatformUpdateProofPolicyError
    ) -> ProveUpdateBootstrapLifecycleError {
        switch error {
        case .operationIdentityMismatch(let field, let expected, let actual):
            return .hostPlatformIdentityMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        case .phaseMismatch(let accepted, let actual):
            return .hostPlatformPhaseMismatch(
                accepted: accepted,
                actual: actual
            )
        case .installationIdentityMismatch(let field, let expected, let actual):
            return .hostPlatformInstallationIdentityMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }
}
