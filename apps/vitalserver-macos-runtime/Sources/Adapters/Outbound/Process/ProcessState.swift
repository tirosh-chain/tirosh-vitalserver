import Application
import Contracts
import Foundation
import Errors

public enum ProcessState {
    // The PoC launcher is a foreground process, so a pid file is enough for now.
    public static func writeCurrentPid(
        pidFile: URL,
        fileStore: RuntimeFileWriting
    ) throws {
        try fileStore.createDirectory(
            at: pidFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileStore.writeData(Data("\(getpid())\n".utf8), to: pidFile, options: .atomic)
    }

    public static func removePidFile(
        _ pidFile: URL,
        fileStore: RuntimeFileWriting,
        log: (String) -> Void = { print($0) }
    ) {
        do {
            try fileStore.removeItem(at: pidFile)
        } catch {
            log("failed to remove VM process pid file pidFile=\(pidFile.path) error=\(error)")
        }
    }

    public static func inspect(
        pidFile: URL,
        fileStore: RuntimeFileReading,
        processExists: (pid_t) -> Bool = defaultProcessExists
    ) -> RuntimeVMProcessState {
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            return .pidFileMissing
        case .loaded(let pid):
            return processExists(pid) ? .running(pid: Int32(pid)) : .stalePid(pid: Int32(pid))
        case .pidFileInvalid(let message):
            return .pidFileInvalid(message)
        case .readFailed(let message):
            return .readFailed(message)
        }
    }

    public static func status(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting
    ) throws {
        switch inspect(pidFile: pidFile, fileStore: fileStore) {
        case .pidFileMissing, .stopped:
            print("stopped")
            return
        case .running(let pid):
            print("running: pid \(pid)")
        case .stalePid:
            print("stale pid file: \(pidFile.path)")
            removePidFile(pidFile, fileStore: fileStore)
        case .pidFileInvalid(let message), .readFailed(let message):
            throw ProcessStateError.runtimeOperationFailed(message)
        case .signalFailed, .stopTimedOut, .unknown:
            throw ProcessStateError.runtimeOperationFailed("invalid VM process status state")
        }
    }

    public static func stop(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting
    ) throws {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            print("already stopped")
            return
        case .loaded(let loadedPid):
            pid = loadedPid
        case .pidFileInvalid(let message), .readFailed(let message):
            throw ProcessStateError.runtimeOperationFailed(message)
        }

        if kill(pid, SIGTERM) == 0 {
            print("sent SIGTERM to pid \(pid)")
        } else {
            print("failed to stop pid \(pid)")
            removePidFile(pidFile, fileStore: fileStore)
        }
    }

    public static func requestStopAndWait(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        signalProcess: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        log: (String) -> Void = { _ in }
    ) throws {
        try throwIfBlockingStopState(requestStopAndWaitState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            signalProcess: signalProcess,
            log: log
        ))
    }

    public static func requestStopAndWaitState(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        signalProcess: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        log: (String) -> Void = { _ in }
    ) -> RuntimeVMProcessState {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            log("VM process pid file is missing; skipping graceful process stop")
            return .pidFileMissing
        case .loaded(let loadedPid):
            pid = loadedPid
        case .pidFileInvalid(let message):
            return .pidFileInvalid(message)
        case .readFailed(let message):
            return .readFailed(message)
        }

        guard processExists(pid) else {
            log("VM process pid file is stale; removing pidFile=\(pidFile.path)")
            removePidFile(pidFile, fileStore: fileStore, log: log)
            return .stalePid(pid: Int32(pid))
        }

        if signalProcess(pid, SIGTERM) == 0 {
            log("sent SIGTERM to VM process pid=\(pid)")
        } else {
            let errorNumber = errno
            if errorNumber == ESRCH {
                log("VM process already stopped pid=\(pid); removing pidFile=\(pidFile.path)")
                removePidFileIfStillReferences(
                    pidFile,
                    expectedPid: pid,
                    fileStore: fileStore,
                    log: log
                )
                return .stalePid(pid: Int32(pid))
            }
            return .signalFailed(pid: Int32(pid), signal: SIGTERM, errnoCode: Int32(errorNumber))
        }

        return waitUntilObservedProcessStoppedState(
            pid: pid,
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            log: log
        )
    }

    public static func forceKillAndWait(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        signalProcess: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        log: (String) -> Void = { _ in }
    ) throws {
        try throwIfBlockingStopState(forceKillAndWaitState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            signalProcess: signalProcess,
            log: log
        ))
    }

    public static func forceKillAndWaitState(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        signalProcess: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        log: (String) -> Void = { _ in }
    ) -> RuntimeVMProcessState {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            log("VM process pid file is missing; skipping forced process stop")
            return .pidFileMissing
        case .loaded(let loadedPid):
            pid = loadedPid
        case .pidFileInvalid(let message):
            return .pidFileInvalid(message)
        case .readFailed(let message):
            return .readFailed(message)
        }

        guard processExists(pid) else {
            log("VM process pid file is stale before forced stop; removing pidFile=\(pidFile.path)")
            removePidFile(pidFile, fileStore: fileStore, log: log)
            return .stalePid(pid: Int32(pid))
        }

        if signalProcess(pid, SIGKILL) == 0 {
            log("sent SIGKILL to VM process pid=\(pid)")
        } else {
            let errorNumber = errno
            if errorNumber == ESRCH {
                log("VM process already stopped before forced stop pid=\(pid); removing pidFile=\(pidFile.path)")
                removePidFileIfStillReferences(
                    pidFile,
                    expectedPid: pid,
                    fileStore: fileStore,
                    log: log
                )
                return .stalePid(pid: Int32(pid))
            }
            return .signalFailed(pid: Int32(pid), signal: SIGKILL, errnoCode: Int32(errorNumber))
        }

        return waitUntilObservedProcessStoppedState(
            pid: pid,
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            log: log
        )
    }

    public static func waitUntilStopped(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        log: (String) -> Void = { print($0) }
    ) throws {
        try throwIfBlockingStopState(waitUntilStoppedState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            log: log
        ))
    }

    public static func waitUntilStoppedAfterServiceUnload(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        log: (String) -> Void = { print($0) }
    ) throws {
        let state = waitUntilStoppedState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            log: log
        )
        switch state {
        case .pidFileMissing:
            log("VM process pid file is missing after VM service unload; treating VM stop as complete")
            return
        default:
            try throwIfBlockingStopState(state)
        }
    }

    public static func waitUntilObservedProcessStopped(
        pid: pid_t,
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        log: (String) -> Void = { print($0) }
    ) throws {
        try throwIfBlockingStopState(waitUntilObservedProcessStoppedState(
            pid: pid,
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            log: log
        ))
    }

    public static func waitUntilStoppedState(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        log: (String) -> Void = { print($0) }
    ) -> RuntimeVMProcessState {
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            return .pidFileMissing
        case .loaded(let pid):
            return waitUntilObservedProcessStoppedState(
                pid: pid,
                pidFile: pidFile,
                fileStore: fileStore,
                timeoutSeconds: timeoutSeconds,
                pollIntervalSeconds: pollIntervalSeconds,
                processExists: processExists,
                log: log
            )
        case .pidFileInvalid(let message):
            return .pidFileInvalid(message)
        case .readFailed(let message):
            return .readFailed(message)
        }
    }

    public static func runningPid(
        pidFile: URL,
        fileStore: RuntimeFileReading,
        processExists: (pid_t) -> Bool = defaultProcessExists
    ) throws -> pid_t {
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            throw ProcessStateError.runtimeOperationFailed(
                "VM process pid file is missing; running process state is not proven"
            )
        case .loaded(let pid):
            guard processExists(pid) else {
                throw ProcessStateError.runtimeOperationFailed("VM process pid file is stale pid=\(pid)")
            }
            return pid
        case .pidFileInvalid(let message), .readFailed(let message):
            throw ProcessStateError.runtimeOperationFailed(message)
        }
    }

    public static func waitUntilObservedProcessStoppedState(
        pid: pid_t,
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        log: (String) -> Void = { print($0) }
    ) -> RuntimeVMProcessState {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var loggedReplacementPid: pid_t?
        var loggedMissingPidFile = false

        while true {
            guard processExists(pid) else {
                removePidFileIfStillReferences(
                    pidFile,
                    expectedPid: pid,
                    fileStore: fileStore,
                    log: log
                )
                return .stopped
            }

            switch readPid(pidFile, fileStore: fileStore) {
            case .missing:
                if !loggedMissingPidFile {
                    log("VM process pid file is missing while waiting for observed VM process exit pid=\(pid)")
                    loggedMissingPidFile = true
                }
            case .loaded(let currentPid):
                if currentPid != pid, loggedReplacementPid != currentPid {
                    log("VM process pid file changed while waiting for observed VM process exit observedPid=\(pid) currentPid=\(currentPid)")
                    loggedReplacementPid = currentPid
                }
            case .pidFileInvalid(let message):
                return .pidFileInvalid(message)
            case .readFailed(let message):
                return .readFailed(message)
            }

            guard Date() < deadline else {
                return .stopTimedOut(pid: Int32(pid), timeoutSeconds: Int(timeoutSeconds))
            }
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
    }

    public static func defaultProcessExists(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func readPid(_ pidFile: URL, fileStore: RuntimeFileReading) -> RuntimePidFileReadResult {
        guard fileStore.fileExists(pidFile) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(pidFile)
            guard
                let text = String(data: data, encoding: .utf8),
                let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return .pidFileInvalid("invalid VM process pid file pidFile=\(pidFile.path)")
            }
            return .loaded(pid)
        } catch {
            return .readFailed("failed to read VM process pid file pidFile=\(pidFile.path) error=\(error.localizedDescription)")
        }
    }

    private static func removePidFileIfStillReferences(
        _ pidFile: URL,
        expectedPid: pid_t,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        log: (String) -> Void
    ) {
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            return
        case .loaded(let currentPid):
            guard currentPid == expectedPid else {
                log("VM process pid file now references another process; leaving pidFile=\(pidFile.path) stoppedPid=\(expectedPid) currentPid=\(currentPid)")
                return
            }
            removePidFile(pidFile, fileStore: fileStore, log: log)
        case .pidFileInvalid(let message), .readFailed(let message):
            log("VM process stopped; pid file cleanup skipped reason=\(message)")
        }
    }

    private static func throwIfBlockingStopState(_ state: RuntimeVMProcessState) throws {
        switch state {
        case .stopped, .stalePid:
            return
        case .pidFileMissing:
            throw ProcessStateError.runtimeOperationFailed(
                "VM process pid file is missing; process stop state is not proven"
            )
        case .pidFileInvalid(let message), .readFailed(let message):
            throw ProcessStateError.runtimeOperationFailed(message)
        case .signalFailed(let pid, let signal, let errnoCode):
            throw ProcessStateError.runtimeOperationFailed(
                "failed to send signal to VM process pid=\(pid) signal=\(signal) errno=\(errnoCode)"
            )
        case .stopTimedOut(let pid, let timeoutSeconds):
            throw ProcessStateError.runtimeOperationFailed(
                "VM process did not stop within \(timeoutSeconds)s pid=\(pid) pidFile state=\(state.rawValue)"
            )
        case .running(let pid):
            throw ProcessStateError.runtimeOperationFailed("VM process is still running pid=\(pid)")
        case .unknown(let value):
            throw ProcessStateError.runtimeOperationFailed("unknown VM process state value=\(value)")
        }
    }
}

private enum RuntimePidFileReadResult {
    case missing
    case loaded(pid_t)
    case pidFileInvalid(String)
    case readFailed(String)
}
