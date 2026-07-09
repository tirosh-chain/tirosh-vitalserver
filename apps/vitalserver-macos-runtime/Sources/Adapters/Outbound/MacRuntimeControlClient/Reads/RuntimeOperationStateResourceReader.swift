import Application
import Contracts
import Foundation
import RuntimeControl

struct RuntimeOperationStateResourceSnapshot: Equatable, Sendable {
    let install: RuntimeInstallStateRead
    let lease: RuntimeOperationLeaseLoadResult
}

protocol RuntimeOperationStateResourceReading: Sendable {
    func loadResourceSnapshot() -> RuntimeOperationStateResourceSnapshot
}

struct HostRuntimeOperationStateResourceReader: RuntimeOperationStateResourceReading, @unchecked Sendable {
    private let operationLeaseReader: any RuntimeOperationLeaseReading
    private let installStateReader: () -> RuntimeInstallStateRead

    init(
        operationLeaseReader: any RuntimeOperationLeaseReading,
        installStateReader: @escaping () -> RuntimeInstallStateRead
    ) {
        self.operationLeaseReader = operationLeaseReader
        self.installStateReader = installStateReader
    }

    static func live(operationLeaseReader: any RuntimeOperationLeaseReading) -> Self {
        return Self(
            operationLeaseReader: operationLeaseReader,
            installStateReader: {
                return RuntimeInstallStateRead.unavailable()
            }
        )
    }

    func loadResourceSnapshot() -> RuntimeOperationStateResourceSnapshot {
        RuntimeOperationStateResourceSnapshot(
            install: installStateReader(),
            lease: operationLeaseReader.loadOperationLease()
        )
    }
}

struct UnavailableRuntimeOperationLeaseReader: RuntimeOperationLeaseReading {
    let reason: String

    func loadOperationLease() -> RuntimeOperationLeaseLoadResult {
        .failed(reason)
    }
}
