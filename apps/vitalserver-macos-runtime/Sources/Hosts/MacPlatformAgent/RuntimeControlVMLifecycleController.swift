import Application
import Contracts
import Foundation
import OutboundAdapters
import RuntimeControl

final class RuntimeControlVMLifecycleController: RuntimeVMLifecycleResourceReading,
    RuntimeVMLifecycleResourceWriting,
    @unchecked Sendable
{
    private let store: SQLiteRuntimeVMLifecycleResourceStore

    init(
        databaseURL: URL = InstalledRuntimePaths.defaultInstalled.runtimeStateDatabase,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = SQLiteRuntimeVMLifecycleResourceStore(
            databaseURL: databaseURL,
            transitionDecider: RuntimeVMLifecycleTransitionUseCase(),
            now: now
        )
    }

    func loadVMLifecycleResource() -> RuntimeVMLifecycleResourceState {
        store.loadVMLifecycleResource()
    }

    @discardableResult
    func writeVMLifecycleResource(
        state: RuntimeVMLifecycleState,
        operation: RuntimeOperation? = nil,
        terminalReason: RuntimeVMLifecycleTerminalReason? = nil,
        message: String? = nil,
        bootWindowSeconds: TimeInterval? = nil
    ) throws -> RuntimeVMLifecycleResourceState {
        try store.writeVMLifecycleResource(
            state: state,
            operation: operation,
            terminalReason: terminalReason,
            message: message,
            bootWindowSeconds: bootWindowSeconds
        )
    }
}

@MainActor
extension RuntimeControlVMLifecycleController: RuntimeVMLifecycleResourceClient {
    func loadVMLifecycleResource() async throws -> RuntimeVMLifecycleResourceState {
        store.loadVMLifecycleResource()
    }

    func putVMLifecycleResource(
        _ document: RuntimeVMLifecycleDocument
    ) async throws -> RuntimeVMLifecycleResourceState {
        try store.putVMLifecycleResource(document)
    }
}
