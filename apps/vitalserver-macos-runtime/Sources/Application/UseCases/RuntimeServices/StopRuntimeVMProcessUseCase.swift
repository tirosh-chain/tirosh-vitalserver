import Contracts
import Foundation

public struct StopRuntimeVMProcessOperations {
    public var readPid: () -> RuntimePidFileReadResult
    public var processExists: (Int32) -> Bool
    public var sendSignal: (Int32, Int32) -> Int32
    public var signalErrorNumber: () -> Int32
    public var removePidFile: () -> Void
    public var removePidFileIfStillReferences: (Int32) -> Void
    public var now: () -> Date
    public var sleep: (TimeInterval) -> Void
    public var log: (String) -> Void

    public init(
        readPid: @escaping () -> RuntimePidFileReadResult,
        processExists: @escaping (Int32) -> Bool,
        sendSignal: @escaping (Int32, Int32) -> Int32,
        signalErrorNumber: @escaping () -> Int32,
        removePidFile: @escaping () -> Void,
        removePidFileIfStillReferences: @escaping (Int32) -> Void,
        now: @escaping () -> Date,
        sleep: @escaping (TimeInterval) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.readPid = readPid
        self.processExists = processExists
        self.sendSignal = sendSignal
        self.signalErrorNumber = signalErrorNumber
        self.removePidFile = removePidFile
        self.removePidFileIfStillReferences = removePidFileIfStillReferences
        self.now = now
        self.sleep = sleep
        self.log = log
    }
}

public struct StopRuntimeVMProcessUseCase {
    public init() {}

    public func requestStopAndWait(
        terminateSignal: Int32,
        noSuchProcessErrorNumber: Int32,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        operations: StopRuntimeVMProcessOperations
    ) throws {
        try throwIfBlocking(requestStopAndWaitState(
            terminateSignal: terminateSignal,
            noSuchProcessErrorNumber: noSuchProcessErrorNumber,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: operations
        ))
    }

    public func requestStopAndWaitState(
        terminateSignal: Int32,
        noSuchProcessErrorNumber: Int32,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        operations: StopRuntimeVMProcessOperations
    ) -> RuntimeVMProcessState {
        switch operations.readPid() {
        case .missing:
            operations.log("VM process pid file is missing; skipping graceful process stop")
            return .pidFileMissing
        case .loaded(let pid):
            return signalAndWait(
                pid: pid,
                signal: terminateSignal,
                noSuchProcessErrorNumber: noSuchProcessErrorNumber,
                alreadyStoppedLog: "VM process already stopped pid=\(pid); removing pid file",
                sentLog: "sent SIGTERM to VM process pid=\(pid)",
                timeoutSeconds: timeoutSeconds,
                pollIntervalSeconds: pollIntervalSeconds,
                operations: operations
            )
        case .pidFileInvalid(let message):
            return .pidFileInvalid(message)
        case .readFailed(let message):
            return .readFailed(message)
        }
    }

    public func forceKillAndWait(
        killSignal: Int32,
        noSuchProcessErrorNumber: Int32,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        operations: StopRuntimeVMProcessOperations
    ) throws {
        try throwIfBlocking(forceKillAndWaitState(
            killSignal: killSignal,
            noSuchProcessErrorNumber: noSuchProcessErrorNumber,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: operations
        ))
    }

    public func forceKillAndWaitState(
        killSignal: Int32,
        noSuchProcessErrorNumber: Int32,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        operations: StopRuntimeVMProcessOperations
    ) -> RuntimeVMProcessState {
        switch operations.readPid() {
        case .missing:
            operations.log("VM process pid file is missing; skipping forced process stop")
            return .pidFileMissing
        case .loaded(let pid):
            return signalAndWait(
                pid: pid,
                signal: killSignal,
                noSuchProcessErrorNumber: noSuchProcessErrorNumber,
                alreadyStoppedLog: "VM process already stopped before forced stop pid=\(pid); removing pid file",
                sentLog: "sent SIGKILL to VM process pid=\(pid)",
                timeoutSeconds: timeoutSeconds,
                pollIntervalSeconds: pollIntervalSeconds,
                operations: operations
            )
        case .pidFileInvalid(let message):
            return .pidFileInvalid(message)
        case .readFailed(let message):
            return .readFailed(message)
        }
    }

    public func waitUntilStopped(
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        allowMissingPidFile: Bool = false,
        operations: StopRuntimeVMProcessOperations
    ) throws {
        let state = waitUntilStoppedState(
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: operations
        )
        if case .pidFileMissing = state, allowMissingPidFile {
            operations.log("VM process pid file is missing after VM service unload; treating VM stop as complete")
            return
        }
        try throwIfBlocking(state)
    }

    public func waitUntilStoppedState(
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        operations: StopRuntimeVMProcessOperations
    ) -> RuntimeVMProcessState {
        switch operations.readPid() {
        case .missing:
            return .pidFileMissing
        case .loaded(let pid):
            return waitUntilObservedProcessStoppedState(
                pid: pid,
                timeoutSeconds: timeoutSeconds,
                pollIntervalSeconds: pollIntervalSeconds,
                operations: operations
            )
        case .pidFileInvalid(let message):
            return .pidFileInvalid(message)
        case .readFailed(let message):
            return .readFailed(message)
        }
    }

    public func waitUntilObservedProcessStopped(
        pid: Int32,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        operations: StopRuntimeVMProcessOperations
    ) throws {
        try throwIfBlocking(waitUntilObservedProcessStoppedState(
            pid: pid,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: operations
        ))
    }

    public func waitUntilObservedProcessStoppedState(
        pid: Int32,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        operations: StopRuntimeVMProcessOperations
    ) -> RuntimeVMProcessState {
        let deadline = operations.now().addingTimeInterval(timeoutSeconds)
        var loggedReplacementPid: Int32?
        var loggedMissingPidFile = false

        while true {
            guard operations.processExists(pid) else {
                operations.removePidFileIfStillReferences(pid)
                return .stopped
            }

            switch operations.readPid() {
            case .missing:
                if !loggedMissingPidFile {
                    operations.log("VM process pid file is missing while waiting for observed VM process exit pid=\(pid)")
                    loggedMissingPidFile = true
                }
            case .loaded(let currentPid):
                if currentPid != pid, loggedReplacementPid != currentPid {
                    operations.log("VM process pid file changed while waiting for observed VM process exit observedPid=\(pid) currentPid=\(currentPid)")
                    loggedReplacementPid = currentPid
                }
            case .pidFileInvalid(let message):
                return .pidFileInvalid(message)
            case .readFailed(let message):
                return .readFailed(message)
            }

            guard operations.now() < deadline else {
                return .stopTimedOut(pid: pid, timeoutSeconds: Int(timeoutSeconds))
            }
            operations.sleep(pollIntervalSeconds)
        }
    }

    private func signalAndWait(
        pid: Int32,
        signal: Int32,
        noSuchProcessErrorNumber: Int32,
        alreadyStoppedLog: String,
        sentLog: String,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval,
        operations: StopRuntimeVMProcessOperations
    ) -> RuntimeVMProcessState {
        guard operations.processExists(pid) else {
            operations.log("VM process pid file is stale; removing pid file")
            operations.removePidFile()
            return .stalePid(pid: pid)
        }

        if operations.sendSignal(pid, signal) == 0 {
            operations.log(sentLog)
        } else {
            let errorNumber = operations.signalErrorNumber()
            if errorNumber == noSuchProcessErrorNumber {
                operations.log(alreadyStoppedLog)
                operations.removePidFileIfStillReferences(pid)
                return .stalePid(pid: pid)
            }
            return .signalFailed(pid: pid, signal: signal, errnoCode: errorNumber)
        }

        return waitUntilObservedProcessStoppedState(
            pid: pid,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: operations
        )
    }

    private func throwIfBlocking(_ state: RuntimeVMProcessState) throws {
        if let message = RuntimeVMProcessStopStatePolicy.blockingFailureMessage(for: state) {
            throw StopRuntimeVMProcessUseCaseError.runtimeOperationFailed(message)
        }
    }
}

public enum StopRuntimeVMProcessUseCaseError: Error, CustomStringConvertible, Equatable {
    case runtimeOperationFailed(String)

    public var description: String {
        switch self {
        case .runtimeOperationFailed(let message):
            return message
        }
    }
}
