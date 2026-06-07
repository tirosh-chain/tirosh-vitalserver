import Application
import Contracts
import Foundation
import Errors

public extension ProcessState {
    static func status(
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

    static func stop(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        signalProcess: (pid_t, Int32) -> Int32 = { kill($0, $1) },
        signalErrorNumber: () -> Int32 = { Int32(errno) }
    ) throws {
        let pid: pid_t
        switch readPid(pidFile, fileStore: fileStore) {
        case .missing:
            print("already stopped")
            return
        case .loaded(let loadedPid):
            pid = pid_t(loadedPid)
        case .pidFileInvalid(let message), .readFailed(let message):
            throw ProcessStateError.runtimeOperationFailed(message)
        }

        if signalProcess(pid, SIGTERM) == 0 {
            print("sent SIGTERM to pid \(pid)")
        } else {
            let errorNumber = signalErrorNumber()
            if errorNumber == ESRCH {
                print("stale pid file: \(pidFile.path)")
                removePidFile(pidFile, fileStore: fileStore)
                return
            }
            throw ProcessStateError.runtimeOperationFailed(
                "failed to stop pid \(pid) errno=\(errorNumber); pid file preserved"
            )
        }
    }
}
