import Foundation
import Core
import Contracts
import HostInfrastructure

enum ProcessState {
    // The PoC launcher is a foreground process, so a pid file is enough for now.
    static func writeCurrentPid(
        pidFile: URL,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) throws {
        try fileStore.createDirectory(
            at: pidFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileStore.writeData(Data("\(getpid())\n".utf8), to: pidFile, options: .atomic)
    }

    static func removePidFile(
        _ pidFile: URL,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore(),
        log: (String) -> Void = { print($0) }
    ) {
        do {
            try fileStore.removeItem(at: pidFile)
        } catch {
            log("failed to remove VM process pid file pidFile=\(pidFile.path) error=\(error)")
        }
    }

    static func status(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) throws {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            print("stopped")
            return
        case .loaded(let loadedPid):
            pid = loadedPid
        case .failed(let message):
            throw LauncherError.runtimeOperationFailed(message)
        }

        if kill(pid, 0) == 0 {
            print("running: pid \(pid)")
        } else {
            print("stale pid file: \(pidFile.path)")
            removePidFile(pidFile, fileStore: fileStore)
        }
    }

    static func stop(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) throws {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            print("already stopped")
            return
        case .loaded(let loadedPid):
            pid = loadedPid
        case .failed(let message):
            throw LauncherError.runtimeOperationFailed(message)
        }

        if kill(pid, SIGTERM) == 0 {
            print("sent SIGTERM to pid \(pid)")
        } else {
            print("failed to stop pid \(pid)")
            removePidFile(pidFile, fileStore: fileStore)
        }
    }

    static func requestStopAndWait(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore(),
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        signalProcess: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        log: (String) -> Void = { _ in }
    ) throws {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            log("VM process pid file is missing; skipping graceful process stop")
            return
        case .loaded(let loadedPid):
            pid = loadedPid
        case .failed(let message):
            throw LauncherError.runtimeOperationFailed(message)
        }

        guard processExists(pid) else {
            log("VM process pid file is stale; removing pidFile=\(pidFile.path)")
            removePidFile(pidFile, fileStore: fileStore, log: log)
            return
        }

        if signalProcess(pid, SIGTERM) == 0 {
            log("sent SIGTERM to VM process pid=\(pid)")
        } else {
            let errorNumber = errno
            if errorNumber == ESRCH {
                log("VM process already stopped pid=\(pid); removing pidFile=\(pidFile.path)")
                removePidFile(pidFile, fileStore: fileStore, log: log)
                return
            }
            throw LauncherError.runtimeOperationFailed(
                "failed to send SIGTERM to VM process pid=\(pid) errno=\(errorNumber)"
            )
        }

        try waitUntilStopped(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            log: log
        )
    }

    static func forceKillAndWait(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore(),
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        signalProcess: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        log: (String) -> Void = { _ in }
    ) throws {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            log("VM process pid file is missing; skipping forced process stop")
            return
        case .loaded(let loadedPid):
            pid = loadedPid
        case .failed(let message):
            throw LauncherError.runtimeOperationFailed(message)
        }

        guard processExists(pid) else {
            log("VM process pid file is stale before forced stop; removing pidFile=\(pidFile.path)")
            removePidFile(pidFile, fileStore: fileStore, log: log)
            return
        }

        if signalProcess(pid, SIGKILL) == 0 {
            log("sent SIGKILL to VM process pid=\(pid)")
        } else {
            let errorNumber = errno
            if errorNumber == ESRCH {
                log("VM process already stopped before forced stop pid=\(pid); removing pidFile=\(pidFile.path)")
                removePidFile(pidFile, fileStore: fileStore, log: log)
                return
            }
            throw LauncherError.runtimeOperationFailed(
                "failed to send SIGKILL to VM process pid=\(pid) errno=\(errorNumber)"
            )
        }

        try waitUntilStopped(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            processExists: processExists,
            log: log
        )
    }

    static func waitUntilStopped(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore(),
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval = 0.5,
        processExists: (pid_t) -> Bool = defaultProcessExists,
        log: (String) -> Void = { print($0) }
    ) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while true {
            let pid: pid_t
            switch readPid(pidFile, fileStore: fileStore) {
            case .missing:
                return
            case .loaded(let loadedPid):
                pid = loadedPid
            case .failed(let message):
                throw LauncherError.runtimeOperationFailed(message)
            }
            guard processExists(pid) else {
                removePidFile(pidFile, fileStore: fileStore, log: log)
                return
            }
            guard Date() < deadline else {
                throw LauncherError.runtimeOperationFailed(
                    "VM process did not stop within \(Int(timeoutSeconds))s pid=\(pid) pidFile=\(pidFile.path)"
                )
            }
            Thread.sleep(forTimeInterval: pollIntervalSeconds)
        }
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
                return .failed("invalid VM process pid file pidFile=\(pidFile.path)")
            }
            return .loaded(pid)
        } catch {
            return .failed("failed to read VM process pid file pidFile=\(pidFile.path) error=\(error.localizedDescription)")
        }
    }

    private static func defaultProcessExists(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}

private enum RuntimePidFileReadResult {
    case missing
    case loaded(pid_t)
    case failed(String)
}
