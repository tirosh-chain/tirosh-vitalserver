import Contracts
import Errors

public struct RuntimeInstallServiceStartInput: Equatable, Sendable {
    public let startAfterInstall: Bool
    public let preventSystemSleep: Bool

    public init(
        startAfterInstall: Bool,
        preventSystemSleep: Bool
    ) {
        self.startAfterInstall = startAfterInstall
        self.preventSystemSleep = preventSystemSleep
    }
}

public struct RuntimeInstallServiceStartOperations {
    public let startLaunchdService: (RuntimeManagedService) throws -> Void
    public let cleanupHostProxyPortBeforeStart: () throws -> Void
    public let log: (String) -> Void

    public init(
        startLaunchdService: @escaping (RuntimeManagedService) throws -> Void,
        cleanupHostProxyPortBeforeStart: @escaping () throws -> Void,
        log: @escaping (String) -> Void
    ) {
        self.startLaunchdService = startLaunchdService
        self.cleanupHostProxyPortBeforeStart = cleanupHostProxyPortBeforeStart
        self.log = log
    }
}

public struct RuntimeInstallServiceStarter {
    public let operations: RuntimeInstallServiceStartOperations

    public init(operations: RuntimeInstallServiceStartOperations) {
        self.operations = operations
    }

    public func start(input: RuntimeInstallServiceStartInput) throws {
        try operations.startLaunchdService(.updateHandoffSupervisor)
        guard input.startAfterInstall else {
            operations.log("start after install disabled")
            return
        }
        if input.preventSystemSleep {
            try operations.startLaunchdService(.sleepPrevention)
        }
        for service in RuntimeManagedService.startOrder {
            if service == .proxy {
                try operations.cleanupHostProxyPortBeforeStart()
            }
            try operations.startLaunchdService(service)
        }
    }
}
