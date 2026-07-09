import Foundation

struct RuntimeObservabilityPaths {
    let runtimeEvents: String
    let runtimeObservabilityDB: String

    init(
        runtimeEvents: String = InstalledRuntimePaths.defaultInstalled.runtimeEvents.path,
        runtimeObservabilityDB: String = InstalledRuntimePaths.defaultInstalled.runtimeObservabilityDB.path
    ) {
        self.runtimeEvents = runtimeEvents
        self.runtimeObservabilityDB = runtimeObservabilityDB
    }
}
