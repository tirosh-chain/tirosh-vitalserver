import Foundation
import Contracts
import Errors

public struct RuntimeHostProxyListenerClassification: Equatable, Sendable {
    public let ownedNginx: [String]
    public let external: [RuntimeHostProxyListener]

    public init(
        ownedNginx: [String],
        external: [RuntimeHostProxyListener]
    ) {
        self.ownedNginx = ownedNginx
        self.external = external
    }
}

public struct CleanRuntimeHostProxyPortOperations {
    public var proxyPort: () -> Int?
    public var proxyServiceState: () -> RuntimeServiceState
    public var expectedProxyNginxPID: () -> RuntimeProxyNginxPIDReadResult
    public var portListenerScan: (Int) -> RuntimeHostProxyListenerScanResult
    public var ownedNginxPathFragments: [String]
    public var nginxCommandLine: (String) -> RuntimeHostProxyNginxCommandLineReadResult
    public var signalOwnedListener: (String, RuntimeHostProxyOwnedListenerSignal) -> Void
    public var sleep: (TimeInterval) -> Void
    public var log: (String) -> Void

    public init(
        proxyPort: @escaping () -> Int?,
        proxyServiceState: @escaping () -> RuntimeServiceState,
        expectedProxyNginxPID: @escaping () -> RuntimeProxyNginxPIDReadResult,
        portListenerScan: @escaping (Int) -> RuntimeHostProxyListenerScanResult,
        ownedNginxPathFragments: [String],
        nginxCommandLine: @escaping (String) -> RuntimeHostProxyNginxCommandLineReadResult,
        signalOwnedListener: @escaping (String, RuntimeHostProxyOwnedListenerSignal) -> Void,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.proxyPort = proxyPort
        self.proxyServiceState = proxyServiceState
        self.expectedProxyNginxPID = expectedProxyNginxPID
        self.portListenerScan = portListenerScan
        self.ownedNginxPathFragments = ownedNginxPathFragments
        self.nginxCommandLine = nginxCommandLine
        self.signalOwnedListener = signalOwnedListener
        self.sleep = sleep
        self.log = log
    }
}

public struct CleanRuntimeHostProxyPortUseCase {
    public init() {}

    public func cleanupBeforeStartingProxy(
        operations: CleanRuntimeHostProxyPortOperations
    ) throws {
        let port = try requiredProxyPort(operations: operations)
        let listeners = try readPortListeners(port: port, operations: operations)
        guard !listeners.isEmpty else {
            operations.log("proxy port cleanup skipped; no listeners on port \(port)")
            return
        }

        let expectedPID = try readExpectedProxyNginxPID(operations: operations)
        let classified = try classify(listeners, expectedPID: expectedPID, operations: operations)
        let serviceState = try readProxyServiceState(operations: operations)
        if serviceState == .loaded, !classified.ownedNginx.isEmpty {
            if classified.external.isEmpty {
                operations.log("proxy port cleanup skipped; configured host proxy already owns port \(port)")
                return
            }
            try throwExternalListenerError(port: port, listeners: classified.external, operations: operations)
        }

        if !classified.ownedNginx.isEmpty {
            operations.log(
                "proxy port cleanup stopping owned nginx listeners port=\(port) pids=\(classified.ownedNginx.joined(separator: ","))"
            )
            _ = try stopOwnedListeners(
                classified.ownedNginx,
                operations: operations,
                false,
                { remainingOwned in
                    "proxy port cleanup force stopping owned nginx listeners port=\(port) pids=\(remainingOwned.joined(separator: ","))"
                },
                {
                    try classify(
                        try readPortListeners(port: port, operations: operations),
                        expectedPID: expectedPID,
                        operations: operations
                    ).ownedNginx
                }
            )
        }

        let remaining = try readPortListeners(port: port, operations: operations)
        guard remaining.isEmpty else {
            let classified = try classify(remaining, expectedPID: expectedPID, operations: operations)
            if !classified.ownedNginx.isEmpty {
                let description = classified.ownedNginx.map { "nginx-\($0)" }.joined(separator: ",")
                operations.log("proxy port cleanup could not stop owned listeners port=\(port) listeners=\(description)")
                throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                    "proxy port \(port) is still held by VitalServer nginx listener(s): \(description). Retry the update or repair Host proxy."
                )
            }
            try throwExternalListenerError(port: port, listeners: classified.external, operations: operations)
        }
        operations.log("proxy port cleanup completed port=\(port)")
    }

    public func cleanupOwnedListenersAfterProxyStop(
        operations: CleanRuntimeHostProxyPortOperations
    ) throws {
        let port = try requiredProxyPort(operations: operations)
        let listeners = try readPortListeners(port: port, operations: operations)
        guard !listeners.isEmpty else {
            operations.log("proxy port cleanup after stop skipped; no listeners on port \(port)")
            return
        }

        let expectedPID = try readExpectedProxyNginxPID(operations: operations)
        let classified = try classify(listeners, expectedPID: expectedPID, operations: operations)
        if !classified.external.isEmpty {
            let description = classified.external.map { "\($0.command)-\($0.pid)" }.joined(separator: ",")
            operations.log("proxy port cleanup after stop leaving external listeners port=\(port) listeners=\(description)")
        }
        guard !classified.ownedNginx.isEmpty else {
            return
        }

        operations.log(
            "proxy port cleanup after stop stopping owned nginx listeners port=\(port) pids=\(classified.ownedNginx.joined(separator: ","))"
        )
        let remaining = try stopOwnedListeners(
            classified.ownedNginx,
            operations: operations,
            true,
            { remainingOwned in
                "proxy port cleanup after stop force stopping owned nginx listeners port=\(port) pids=\(remainingOwned.joined(separator: ","))"
            },
            {
                try classify(
                    try readPortListeners(port: port, operations: operations),
                    expectedPID: expectedPID,
                    operations: operations
                ).ownedNginx
            }
        )
        guard remaining.isEmpty else {
            let description = remaining.map { "nginx-\($0)" }.joined(separator: ",")
            operations.log("proxy port cleanup after stop could not stop owned listeners port=\(port) listeners=\(description)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "proxy port \(port) is still held by VitalServer nginx listener(s): \(description). Retry clean uninstall."
            )
        }
        operations.log("proxy port cleanup after stop completed port=\(port)")
    }

    private func readPortListeners(
        port: Int,
        operations: CleanRuntimeHostProxyPortOperations
    ) throws -> [RuntimeHostProxyListener] {
        switch operations.portListenerScan(port) {
        case .clear:
            return []
        case .loaded(let listeners):
            return listeners
        case .unavailable:
            operations.log("proxy port cleanup failed; lsof is unavailable for port \(port)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to inspect proxy port \(port) listeners because lsof is unavailable. Retry the update or repair Host proxy."
            )
        case .inspectionFailed(let reason):
            operations.log("proxy port cleanup failed to inspect lsof path port=\(port) reason=\(reason)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to inspect proxy port \(port) listeners because lsof path inspection failed. Retry the update or repair Host proxy."
            )
        case .commandFailed(let exitCode, let reason):
            operations.log("proxy port listener scan failed port=\(port) exitCode=\(exitCode) reason=\(reason)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to inspect proxy port \(port) listeners with lsof exitCode=\(exitCode). Retry the update or repair Host proxy."
            )
        case .malformedOutput(let exitCode, let reason):
            operations.log("proxy port listener scan output malformed port=\(port) exitCode=\(exitCode) reason=\(reason)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to inspect proxy port \(port) listeners with malformed lsof output. Retry the update or repair Host proxy."
            )
        }
    }

    private func stopOwnedListeners(
        _ pids: [String],
        operations: CleanRuntimeHostProxyPortOperations,
        _ verifyAfterForceStop: Bool,
        _ forceLogMessage: ([String]) -> String,
        _ remainingOwned: () throws -> [String]
    ) throws -> [String] {
        signal(pids, .terminate, operations: operations)
        operations.sleep(1)
        let remaining = try remainingOwned()
        if !remaining.isEmpty {
            operations.log(forceLogMessage(remaining))
            signal(remaining, .kill, operations: operations)
            operations.sleep(1)
        }
        return verifyAfterForceStop ? try remainingOwned() : remaining
    }

    private func signal(
        _ pids: [String],
        _ signal: RuntimeHostProxyOwnedListenerSignal,
        operations: CleanRuntimeHostProxyPortOperations
    ) {
        for pid in pids {
            operations.signalOwnedListener(pid, signal)
        }
    }

    private func classify(
        _ listeners: [RuntimeHostProxyListener],
        expectedPID: String?,
        operations: CleanRuntimeHostProxyPortOperations
    ) throws -> RuntimeHostProxyListenerClassification {
        var commandLineReadResults: [String: RuntimeHostProxyNginxCommandLineReadResult] = [:]
        for listener in listeners where listener.command == "nginx" && listener.pid != expectedPID {
            commandLineReadResults[listener.pid] = operations.nginxCommandLine(listener.pid)
        }

        switch RuntimeHostProxyNginxOwnershipPolicy.classify(
            listeners: listeners,
            expectedPID: expectedPID,
            ownedNginxPathFragments: operations.ownedNginxPathFragments,
            commandLineReadResults: commandLineReadResults
        ) {
        case .classified(let classification):
            return classification
        case .commandLineReadMissing(let pid):
            operations.log("proxy port cleanup failed to inspect nginx command line pid=\(pid) reason=missing command line observation")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to inspect Host proxy nginx command line pid=\(pid). Retry the update or repair Host proxy."
            )
        case .commandLineReadFailed(let pid, let reason):
            operations.log("proxy port cleanup failed to inspect nginx command line pid=\(pid) \(reason)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to inspect Host proxy nginx command line pid=\(pid). Retry the update or repair Host proxy."
            )
        case .commandLineEmpty(let pid):
            operations.log("proxy port cleanup failed to inspect nginx command line pid=\(pid) reason=empty command")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to inspect Host proxy nginx command line pid=\(pid). Retry the update or repair Host proxy."
            )
        }
    }

    private func requiredProxyPort(
        operations: CleanRuntimeHostProxyPortOperations
    ) throws -> Int {
        guard let port = operations.proxyPort() else {
            operations.log("proxy port cleanup failed; configured Host proxy port is unavailable")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to read configured Host proxy port. Retry the update or repair Host proxy."
            )
        }
        return port
    }

    private func readProxyServiceState(
        operations: CleanRuntimeHostProxyPortOperations
    ) throws -> RuntimeServiceState {
        let state = operations.proxyServiceState()
        guard !state.isReadFailure else {
            operations.log("proxy port cleanup failed to read proxy service state state=\(state.rawValue)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to read Host proxy launchd service state. Retry the update or repair Host proxy."
            )
        }
        return state
    }

    private func readExpectedProxyNginxPID(
        operations: CleanRuntimeHostProxyPortOperations
    ) throws -> String? {
        switch operations.expectedProxyNginxPID() {
        case .loaded(let pid):
            return pid
        case .missing, .empty:
            return nil
        case .readFailed(let message):
            operations.log("proxy port cleanup failed to read expected nginx pid error=\(message)")
            throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
                "failed to read expected Host proxy nginx PID. Retry the update or repair Host proxy."
            )
        }
    }

    private func throwExternalListenerError(
        port: Int,
        listeners: [RuntimeHostProxyListener],
        operations: CleanRuntimeHostProxyPortOperations
    ) throws -> Never {
        let description = listeners.map(\.hyphenDescription).joined(separator: ",")
        operations.log("proxy port cleanup blocked by external listeners port=\(port) listeners=\(description)")
        throw RuntimeHostProxyPortCleanerError.runtimeOperationFailed(
            "proxy port \(port) is in use by external listener(s): \(description). Stop that process or change the Host proxy port."
        )
    }
}
