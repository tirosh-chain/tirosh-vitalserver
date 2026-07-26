import Application
import Contracts
import Foundation
import RuntimeControl

struct PlatformOperationStateResourceSnapshot: Equatable, Sendable {
    let install: RuntimeInstallStateRead
    let lease: RuntimeOperationLeaseLoadResult
    let workflow: RuntimeWorkflowOperationStateReadResult
}

protocol PlatformOperationStateResourceReading: Sendable {
    func loadResourceSnapshot() -> PlatformOperationStateResourceSnapshot
}

struct HostPlatformOperationStateResourceReader: PlatformOperationStateResourceReading, @unchecked Sendable {
    private let operationLeaseReader: any RuntimeOperationLeaseReading
    private let workflowOperationStateReader: any RuntimeWorkflowOperationStateReading
    private let installStateReader: () -> RuntimeInstallStateRead

    init(
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading,
        installStateReader: @escaping () -> RuntimeInstallStateRead
    ) {
        self.operationLeaseReader = operationLeaseReader
        self.workflowOperationStateReader = workflowOperationStateReader
        self.installStateReader = installStateReader
    }

    static func live(
        operationLeaseReader: any RuntimeOperationLeaseReading,
        workflowOperationStateReader: any RuntimeWorkflowOperationStateReading
    ) -> Self {
        return Self(
            operationLeaseReader: operationLeaseReader,
            workflowOperationStateReader: workflowOperationStateReader,
            installStateReader: {
                return RuntimeInstallStateRead.unavailable()
            }
        )
    }

    func loadResourceSnapshot() -> PlatformOperationStateResourceSnapshot {
        PlatformOperationStateResourceSnapshot(
            install: installStateReader(),
            lease: operationLeaseReader.loadOperationLease(),
            workflow: workflowOperationStateReader.loadLatestOperationState()
        )
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
