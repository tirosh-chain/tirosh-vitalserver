import Foundation
import RuntimeControl
import Application
import Contracts
import Errors

struct RuntimePaths {
    let launcher: String
    let uninstaller: String
    let runtimeState: String
    let runtimeStatus: String
    let redisRelayStatus: String
    let runtimeInstallState: String
    let runtimeOperationLease: String
    let runtimeEvents: String
    let runtimeObservabilityDB: String

    init(
        launcher: String = RuntimeControlClientConstants.Paths.launcher,
        uninstaller: String = RuntimeControlClientConstants.Paths.uninstaller,
        runtimeState: String = RuntimeControlClientConstants.Paths.runtimeState,
        runtimeStatus: String = RuntimeControlClientConstants.Paths.runtimeStatus,
        redisRelayStatus: String = RuntimeControlClientConstants.Paths.redisRelayStatus,
        runtimeInstallState: String = RuntimeControlClientConstants.Paths.runtimeInstallState,
        runtimeOperationLease: String = RuntimeControlClientConstants.Paths.runtimeOperationLease,
        runtimeEvents: String = RuntimeControlClientConstants.Paths.runtimeEvents,
        runtimeObservabilityDB: String = RuntimeControlClientConstants.Paths.runtimeObservabilityDB
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.redisRelayStatus = redisRelayStatus
        self.runtimeInstallState = runtimeInstallState
        self.runtimeOperationLease = runtimeOperationLease
        self.runtimeEvents = runtimeEvents
        self.runtimeObservabilityDB = runtimeObservabilityDB
    }
}
