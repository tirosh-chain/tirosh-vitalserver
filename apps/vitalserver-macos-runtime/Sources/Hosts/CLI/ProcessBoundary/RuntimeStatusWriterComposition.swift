import Contracts
import Foundation
import OutboundAdapters
import Errors

public struct RuntimeStatusWriterCompositionOperations {
    let reporter: RuntimeStatusReporter
    let timestamp: () -> String
    let runtimeVersion: () -> String
    let healthSnapshot: () -> RuntimeHealthSnapshot
    let latestBackup: () throws -> URL?

    public init(
        reporter: RuntimeStatusReporter,
        timestamp: @escaping () -> String,
        runtimeVersion: @escaping () -> String,
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot,
        latestBackup: @escaping () throws -> URL?
    ) {
        self.reporter = reporter
        self.timestamp = timestamp
        self.runtimeVersion = runtimeVersion
        self.healthSnapshot = healthSnapshot
        self.latestBackup = latestBackup
    }
}

public enum RuntimeStatusWriterComposition {
    public static func make(
        operations: RuntimeStatusWriterCompositionOperations
    ) -> RuntimeStatusWriter {
        RuntimeStatusWriter(
            reporter: operations.reporter,
            timestamp: operations.timestamp,
            runtimeVersion: operations.runtimeVersion,
            healthSnapshot: operations.healthSnapshot,
            latestBackup: operations.latestBackup
        )
    }
}
