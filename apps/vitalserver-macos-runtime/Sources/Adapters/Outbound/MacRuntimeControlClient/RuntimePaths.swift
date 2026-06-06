import Foundation
import RuntimeControl
import Application
import Contracts
import Domain
import Errors

struct RuntimePaths {
    let launcher: String
    let uninstaller: String
    let runtimeState: String
    let runtimeStatus: String
    let runtimeEvents: String
    let runtimeObservabilityDB: String

    init(
        launcher: String = RuntimeAdapterConstants.Paths.launcher,
        uninstaller: String = RuntimeAdapterConstants.Paths.uninstaller,
        runtimeState: String = RuntimeAdapterConstants.Paths.runtimeState,
        runtimeStatus: String = RuntimeAdapterConstants.Paths.runtimeStatus,
        runtimeEvents: String = RuntimeAdapterConstants.Paths.runtimeEvents,
        runtimeObservabilityDB: String = RuntimeAdapterConstants.Paths.runtimeObservabilityDB
    ) {
        self.launcher = launcher
        self.uninstaller = uninstaller
        self.runtimeState = runtimeState
        self.runtimeStatus = runtimeStatus
        self.runtimeEvents = runtimeEvents
        self.runtimeObservabilityDB = runtimeObservabilityDB
    }
}
