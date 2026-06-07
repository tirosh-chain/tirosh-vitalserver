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
    let runtimeEvents: String
    let runtimeObservabilityDB: String

    init(
        launcher: String = RuntimeControlClientConstants.Paths.launcher,
        uninstaller: String = RuntimeControlClientConstants.Paths.uninstaller,
        runtimeState: String = RuntimeControlClientConstants.Paths.runtimeState,
        runtimeStatus: String = RuntimeControlClientConstants.Paths.runtimeStatus,
        runtimeEvents: String = RuntimeControlClientConstants.Paths.runtimeEvents,
        runtimeObservabilityDB: String = RuntimeControlClientConstants.Paths.runtimeObservabilityDB
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.runtimeEvents = runtimeEvents
        self.runtimeObservabilityDB = runtimeObservabilityDB
    }
}
