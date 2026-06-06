import Application
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
        statusReporter: RuntimeStatusReporter,
        guestGateway: RuntimeGuestGateway,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) -> RuntimeManagedOperationGuardComposition {
        RuntimeManagedOperationGuardComposition(
            graceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            operations: GuardManagedRuntimeOperationOperations(
                loadStatus: statusReporter.loadStatusResult,
                activeGuestBootstrap: {
                    activeGuestBootstrap(guestGateway: guestGateway, log: log)
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
        guestGateway: RuntimeGuestGateway,
        log: (String) -> Void
    ) -> RuntimeGuestBootstrapOperation? {
        guard case .loaded(let bootstrapResult) = guestGateway.loadBootstrapResultDocument(),
              bootstrapResult.status == .running
        else {
            return nil
        }
        guard let bootstrapBootID = bootstrapResult.bootID, !bootstrapBootID.isEmpty else {
            log("watchdog guest bootstrap guard ignored result without bootID")
            return nil
        }
        if case .loaded(let runtimeState) = guestGateway.loadRuntimeStateDocument(),
           let runtimeBootID = runtimeState.bootID,
           !runtimeBootID.isEmpty,
           runtimeBootID != bootstrapBootID {
            log("watchdog guest bootstrap guard ignored stale result bootID=\(bootstrapBootID) runtimeBootID=\(runtimeBootID)")
            return nil
        }
        let updatedAt = bootstrapResult.updatedAt.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        return RuntimeGuestBootstrapOperation(
            operation: bootstrapResult.operation ?? .install,
            updatedAt: updatedAt
        )
    }
}
