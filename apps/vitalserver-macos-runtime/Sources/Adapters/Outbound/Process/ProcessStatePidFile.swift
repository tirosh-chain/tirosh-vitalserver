import Application
import Contracts
import Foundation

extension ProcessState {
    // Host owns this pid file and verifies the referenced process before treating it as runtime state.
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
            return processExists(pid_t(pid)) ? .running(pid: pid) : .stalePid(pid: pid)
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
            guard processExists(pid_t(pid)) else {
                throw ProcessStateError.runtimeOperationFailed("VM process pid file is stale pid=\(pid)")
            }
            return pid_t(pid)
        case .pidFileInvalid(let message), .readFailed(let message):
            throw ProcessStateError.runtimeOperationFailed(message)
        }
    }

    static func readPid(_ pidFile: URL, fileStore: RuntimeFileReading) -> RuntimePidFileReadResult {
        let state = fileStore.pathState(at: pidFile)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .readFailed("failed to inspect VM process pid file pidFile=\(pidFile.path) error=\(reason)")
        case .directory, .other, .unknown:
            return .readFailed("VM process pid file path state is unexpected pidFile=\(pidFile.path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(pidFile)
            guard
                let text = String(data: data, encoding: .utf8),
                let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return .pidFileInvalid("invalid VM process pid file pidFile=\(pidFile.path)")
            }
            return .loaded(Int32(pid))
        } catch {
            return .readFailed("failed to read VM process pid file pidFile=\(pidFile.path) error=\(error.localizedDescription)")
        }
    }

    static func removePidFileIfStillReferences(
        _ pidFile: URL,
        expectedPid: pid_t,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        log: (String) -> Void
    ) {
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            return
        case .loaded(let currentPid):
            guard currentPid == Int32(expectedPid) else {
                log("VM process pid file now references another process; leaving pidFile=\(pidFile.path) stoppedPid=\(expectedPid) currentPid=\(currentPid)")
                return
            }
            removePidFile(pidFile, fileStore: fileStore, log: log)
        case .pidFileInvalid(let message), .readFailed(let message):
            log("VM process stopped; pid file cleanup skipped reason=\(message)")
        }
    }

    public static func stopOperations(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        processExists: @escaping (pid_t) -> Bool = defaultProcessExists,
        signalProcess: @escaping (pid_t, Int32) -> Int32 = { kill($0, $1) },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        log: @escaping (String) -> Void = { _ in }
    ) -> StopRuntimeVMProcessOperations {
        StopRuntimeVMProcessOperations(
            readPid: {
                readPid(pidFile, fileStore: fileStore)
            },
            processExists: { pid in
                processExists(pid_t(pid))
            },
            sendSignal: { pid, signal in
                signalProcess(pid_t(pid), signal)
            },
            signalErrorNumber: {
                Int32(errno)
            },
            removePidFile: {
                removePidFile(pidFile, fileStore: fileStore, log: log)
            },
            removePidFileIfStillReferences: { expectedPid in
                removePidFileIfStillReferences(
                    pidFile,
                    expectedPid: pid_t(expectedPid),
                    fileStore: fileStore,
                    log: log
                )
            },
            now: now,
            sleep: sleep,
            log: log
        )
    }
}
