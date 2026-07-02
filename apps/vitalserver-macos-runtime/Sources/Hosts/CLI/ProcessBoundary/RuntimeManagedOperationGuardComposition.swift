import Application
import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import Errors

public struct RuntimeManagedOperationGuardComposition {
    private let graceSeconds: TimeInterval
    private let operations: GuardManagedRuntimeOperationOperations

    public init(
        graceSeconds: TimeInterval,
        operations: GuardManagedRuntimeOperationOperations
    ) {
        self.graceSeconds = graceSeconds
        self.operations = operations
    }

    public static func make(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore,
        statusReporter: RuntimeStatusReporter,
        operationLeaseRepository: RuntimeOperationLeaseRepository,
        guestBootstrapResultReader: any RuntimeGuestBootstrapResultReader,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) -> RuntimeManagedOperationGuardComposition {
        RuntimeManagedOperationGuardComposition(
            graceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            operations: GuardManagedRuntimeOperationOperations(
                loadOperationLease: operationLeaseRepository.loadResult,
                loadStatus: statusReporter.loadStatusResult,
                activeGuestBootstrap: {
                    activeGuestBootstrap(
                        guestBootstrapResultReader: guestBootstrapResultReader,
                        vmLifecycle: RuntimeVMLifecycleStore(
                            url: installedPaths.vmLifecycle,
                            fileStore: fileStore
                        ).load(),
                        log: log
                    )
                },
                now: now,
                log: log
            )
        )
    }

    public func activeOperation() -> RuntimeOperation? {
        GuardManagedRuntimeOperationUseCase().activeOperation(
            graceSeconds: graceSeconds,
            operations: operations
        )
    }

    private static func activeGuestBootstrap(
        guestBootstrapResultReader: any RuntimeGuestBootstrapResultReader,
        vmLifecycle: RuntimeGuestDocumentLoadResult<RuntimeVMLifecycleDocument>,
        log: (String) -> Void
    ) -> RuntimeGuestBootstrapOperation? {
        guard case .loaded(let bootstrapResult) = guestBootstrapResultReader.loadBootstrapResultDocument(),
              bootstrapResult.status == .running
        else {
            return nil
        }
        guard let bootstrapBootID = bootstrapResult.bootID, !bootstrapBootID.isEmpty else {
            log("watchdog guest bootstrap guard ignored result without bootID")
            return nil
        }
        let lifecycle: RuntimeVMLifecycleDocument
        switch vmLifecycle {
        case .loaded(let document):
            lifecycle = document
        case .missing:
            log("watchdog guest bootstrap guard ignored missing VM lifecycle operation=\((bootstrapResult.operation ?? .install).rawValue)")
            return nil
        case .failed(let reason):
            log("watchdog guest bootstrap guard ignored VM lifecycle read failure operation=\((bootstrapResult.operation ?? .install).rawValue) error=\(reason)")
            return nil
        }
        if let lifecycleBootID = lifecycle.bootID,
           !lifecycleBootID.isEmpty,
           lifecycleBootID != bootstrapBootID {
            log("watchdog guest bootstrap guard ignored stale result bootID=\(bootstrapBootID) lifecycleBootID=\(lifecycleBootID)")
            return nil
        }
        let updatedAt = bootstrapResult.updatedAt.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        return RuntimeGuestBootstrapOperation(
            operation: bootstrapResult.operation ?? .install,
            updatedAt: updatedAt,
            vmLifecycle: lifecycle
        )
    }
}
