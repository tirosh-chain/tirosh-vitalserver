import RuntimeCore

struct RuntimeServiceControlRunner {
    var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    var stopRuntimeServices: () throws -> Void
    var waitForHealth: (RuntimeServiceRestartPolicy) throws -> Void
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var log: (String) -> Void

    func startAll() throws {
        let policy = RuntimeServiceRestartPolicy(
            restartVM: true,
            restartProxy: true,
            restartWatchdog: true
        )
        log("runtime services start requested")
        try writeStatus(.recovering, .startServices, "runtime services start requested")
        try startRuntimeServices(policy)
        try writeStatus(.recovering, .startServices, "runtime services start dispatched")
        log("runtime services start dispatched")
    }

    func stopAll() throws {
        log("runtime services stop requested")
        try stopRuntimeServices()
        try writeStatus(.degraded, .stopServices, "runtime services stopped")
        log("runtime services stopped")
    }
}
