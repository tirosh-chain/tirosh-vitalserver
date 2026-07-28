import Application
import Contracts
import Foundation
import RuntimeControl

struct PlatformOperationStateResourceSnapshot: Equatable, Sendable {
    let install: RuntimeInstallStateRead
    let lease: RuntimeOperationLeaseLoadResult
    let workflow: RuntimeWorkflowOperationStateReadResult
    let stableUpdate: UpdateBootstrapJournalReadResult
}

protocol PlatformOperationStateResourceReading: Sendable {
    func loadResourceSnapshot() -> PlatformOperationStateResourceSnapshot
}

struct HostPlatformOperationStateResourceReader: PlatformOperationStateResourceReading, @unchecked Sendable {
    private let operationLeaseReader: any RuntimeOperationLeaseReading
    private let workflowOperationStateReader: any RuntimeWorkflowOperationStateReading
    private let stableUpdateJournalReader: any UpdateBootstrapJournalReading
    private let installStateReader: () -> RuntimeInstallStateRead

    init(
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading,
        stableUpdateJournalReader: any UpdateBootstrapJournalReading,
        installStateReader: @escaping () -> RuntimeInstallStateRead
    ) {
        self.operationLeaseReader = operationLeaseReader
        self.workflowOperationStateReader = workflowOperationStateReader
        self.stableUpdateJournalReader = stableUpdateJournalReader
        self.installStateReader = installStateReader
    }

    static func live(
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading,
        stableUpdateJournalReader: any UpdateBootstrapJournalReading
    ) -> Self {
        return Self(
            operationLeaseReader: operationLeaseReader,
            workflowOperationStateReader: workflowOperationStateReader,
            stableUpdateJournalReader: stableUpdateJournalReader,
            installStateReader: {
                return RuntimeInstallStateRead.unavailable()
            }
        )
    }

    func loadResourceSnapshot() -> PlatformOperationStateResourceSnapshot {
        PlatformOperationStateResourceSnapshot(
            install: installStateReader(),
            lease: operationLeaseReader.loadOperationLease(),
            workflow: workflowOperationStateReader.loadLatestOperationState(),
            stableUpdate: stableUpdateJournalReader.loadLatestUpdateBootstrapJournal()
        )
    }
}

public struct UnavailableUpdateBootstrapJournalReader: UpdateBootstrapJournalReading {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func loadUpdateBootstrapJournal(id _: String) -> UpdateBootstrapJournalReadResult {
        .failed(reason: reason)
    }

    public func loadLatestUpdateBootstrapJournal() -> UpdateBootstrapJournalReadResult {
        .failed(reason: reason)
    }
}

public struct UnavailableRuntimeWorkflowOperationStateReader: RuntimeWorkflowOperationStateReading {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func loadOperationState(operationID: String) -> RuntimeWorkflowOperationStateReadResult {
        .failed(reason)
    }

    public func loadLatestOperationState() -> RuntimeWorkflowOperationStateReadResult {
        .failed(reason)
    }

    public func loadLatestOperationState(operation: RuntimeOperation) -> RuntimeWorkflowOperationStateReadResult {
        .failed(reason)
    }
}

struct UnavailableRuntimeOperationLeaseReader: RuntimeOperationLeaseReading {
    let reason: String

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        .failed(reason)
    }
}
