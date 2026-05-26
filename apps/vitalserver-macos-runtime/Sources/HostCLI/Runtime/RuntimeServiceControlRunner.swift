import Core
import Contracts

struct RuntimeServiceControlRunner {
    var startRuntimeServices: (RuntimeServiceRestartPolicy) throws -> Void
    var stopRuntimeServices: () throws -> Void
    var writeStatus: (RuntimeStatusLevel, RuntimeOperation, String) throws -> Void
    var log: (String) -> Void

    func run(_ command: RuntimeServiceControlCommand) throws {
        switch command {
        case .repairAll:
            try repairAll()
        case .startAll:
            try startAll()
        case .stopAll:
            try stopAll()
        }
    }

    private func repairAll() throws {
        let policy = RuntimeServiceRestartPolicy(
            restartVM: true,
            restartProxy: true,
            restartWatchdog: true
        )
        log("runtime services repair requested")
        try writeStatus(.recovering, .repairServices, "runtime services repair requested")
        try stopRuntimeServices()
        try startRuntimeServices(policy)
        try writeStatus(.recovering, .repairServices, "runtime services repair dispatched")
        log("runtime services repair dispatched")
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
