import Application
import Contracts
import Foundation
import Workflow

public enum RuntimeManagedOperationGuardComposition {
    public static func make(
        statusReporter: RuntimeStatusReporter,
        guestGateway: RuntimeGuestGateway,
        now: @escaping () -> Date,
        log: @escaping (String) -> Void
    ) -> RuntimeManagedOperationGuard {
        RuntimeManagedOperationGuard(
            statusReporter: statusReporter,
            activeGuestBootstrap: {
                activeGuestBootstrap(guestGateway: guestGateway, log: log)
            },
            now: now,
            graceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            log: log
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
