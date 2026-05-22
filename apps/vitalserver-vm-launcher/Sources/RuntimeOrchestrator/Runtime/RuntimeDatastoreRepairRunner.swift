import Foundation
import RuntimeCore

struct RuntimeDatastoreRepairRunner {
    var prepareGuestRunDirectory: () throws -> Void
    var removePreviousResult: () throws -> Void
    var writeRequest: (String, String) throws -> Void
    var isVMServiceLoaded: () -> Bool
    var startVMService: () -> Void
    var restartVMService: () -> Void
    var waitForResult: (String) throws -> Void
    var restartProxyService: () -> Void
    var restartWatchdogService: () -> Void
    var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var makeRequestID: () -> String
    var timestamp: () -> String
    var log: (String) -> Void

    func run() throws {
        log("datastore repair requested")
        try prepareGuestRunDirectory()
        try? removePreviousResult()
        try writeStatus(.recovering, .repairDatastore, "datastore repair requested")

        let requestID = makeRequestID()
        try writeRequest(requestID, timestamp())

        if isVMServiceLoaded() {
            restartVMService()
        } else {
            startVMService()
        }

        try waitForResult(requestID)
        restartProxyService()
        restartWatchdogService()
        try waitForHealth(RuntimeServiceRestartPolicy(
            restartVM: true,
            restartProxy: true,
            restartWatchdog: true
        ))
        try writeStatus(.healthy, .repairDatastore, "datastore repair completed")
        log("datastore repair completed")
    }
}
