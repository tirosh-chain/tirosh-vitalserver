import Foundation
import Core
import Contracts
import HostInfrastructure

enum ProcessState {
    // The PoC launcher is a foreground process, so a pid file is enough for now.
    static func writeCurrentPid(
        pidFile: URL,
        fileStore: RuntimeFileWriting = LocalRuntimeFileStore()
    ) throws {
        try fileStore.createDirectory(
            at: pidFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileStore.writeData(Data("\(getpid())\n".utf8), to: pidFile, options: .atomic)
    }

    static func removePidFile(
        _ pidFile: URL,
        fileStore: RuntimeFileWriting = LocalRuntimeFileStore()
    ) {
        try? fileStore.removeItem(at: pidFile)
    }

    static func status(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting = LocalRuntimeFileStore()
    ) throws {
        guard let pid = readPid(pidFile, fileStore: fileStore) else {
            print("stopped")
            return
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
        fileStore: RuntimeFileReading & RuntimeFileWriting = LocalRuntimeFileStore()
    ) throws {
        guard let pid = readPid(pidFile, fileStore: fileStore) else {
            print("already stopped")
            return
        }

        if kill(pid, SIGTERM) == 0 {
            print("sent SIGTERM to pid \(pid)")
        } else {
            print("failed to stop pid \(pid)")
            removePidFile(pidFile, fileStore: fileStore)
        }
    }

    private static func readPid(_ pidFile: URL, fileStore: RuntimeFileReading) -> pid_t? {
        guard
            let data = try? fileStore.readData(pidFile),
            let text = String(data: data, encoding: .utf8),
            let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        return pid
    }
}
