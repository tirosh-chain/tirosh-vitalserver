import Foundation
import Core
import Contracts

struct RuntimeDatastoreRepairRunner {
    var requireCapability: () throws -> Void
    var prepareGuestRunDirectory: () throws -> Void
    var removePreviousResult: () throws -> Void
    var writeRequest: (RuntimeDatastoreRepairRequest) throws -> Void
    var isVMServiceLoaded: () -> Bool
    var startVMService: () throws -> Void
    var restartVMService: () throws -> Void
    var waitForResult: (RuntimeDatastoreRepairRequest) throws -> Void
    var restartProxyService: () throws -> Void
    var restartWatchdogService: () throws -> Void
    var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var makeRequestID: () -> String
    var timestamp: () -> String
    var log: (String) -> Void

    func run() throws {
        log("datastore repair requested")
        try requireCapability()
        try prepareGuestRunDirectory()
        try removePreviousResult()
        try writeStatus(.recovering, .repairDatastore, "datastore repair requested")

        let request = RuntimeDatastoreRepairRequest(id: makeRequestID(), requestedAt: timestamp())
        try writeRequest(request)

        if isVMServiceLoaded() {
            try restartVMService()
        } else {
            try startVMService()
        }

        try waitForResult(request)
        try restartProxyService()
        try restartWatchdogService()
        try waitForHealth(RuntimeServiceRestartPolicy(
            restartVM: true,
            restartProxy: true,
            restartWatchdog: true
        ))
        try writeStatus(.healthy, .repairDatastore, "datastore repair completed")
        log("datastore repair completed")
    }
}
