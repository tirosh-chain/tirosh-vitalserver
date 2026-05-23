import RuntimeCore
import RuntimeContracts

struct RuntimeServiceControlRunner {
    var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    var stopRuntimeServices: () throws -> Void
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var log: (String) -> Void

    func run(_ command: RuntimeServiceControlCommand) throws {
        switch command {
        case .startAll:
            try startAll()
        case .stopAll:
            try stopAll()
        }
    }

    private func startAll() throws {
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

    private func stopAll() throws {
        log("runtime services stop requested")
        try stopRuntimeServices()
        try writeStatus(.degraded, .stopServices, "runtime services stopped")
        log("runtime services stopped")
    }
}
