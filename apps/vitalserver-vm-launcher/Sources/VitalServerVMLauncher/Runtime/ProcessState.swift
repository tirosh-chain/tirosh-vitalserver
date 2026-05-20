import Foundation

enum ProcessState {
    // The PoC launcher is a foreground process, so a pid file is enough for now.
    static func writeCurrentPid(pidFile: URL) throws {
        try FileManager.default.createDirectory(
            at: pidFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "\(getpid())\n".write(to: pidFile, atomically: true, encoding: .utf8)
    }

    static func removePidFile(_ pidFile: URL) {
        try? FileManager.default.removeItem(at: pidFile)
    }

    static func status(pidFile: URL) throws {
        guard let pid = readPid(pidFile) else {
            print("stopped")
            return
        }

        if kill(pid, 0) == 0 {
            print("running: pid \(pid)")
        } else {
            print("stale pid file: \(pidFile.path)")
        }
    }

    static func stop(pidFile: URL) throws {
        guard let pid = readPid(pidFile) else {
            print("already stopped")
            return
        }

        if kill(pid, SIGTERM) == 0 {
            print("sent SIGTERM to pid \(pid)")
        } else {
            print("failed to stop pid \(pid)")
        }
    }

    private static func readPid(_ pidFile: URL) -> pid_t? {
        guard
            let data = try? Data(contentsOf: pidFile),
            let text = String(data: data, encoding: .utf8),
            let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        return pid
    }
}
