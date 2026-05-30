import Foundation
import Core

struct RuntimeHostProxyPortCleaner {
    var proxyPort: () -> Int
    var proxyServiceLoaded: () -> Bool
    var expectedProxyNginxPID: () -> String?
    var ownedNginxPathFragments: [String]
    var runProcess: (String, [String]) -> RuntimeProcessResult
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var log: (String) -> Void

    func cleanupBeforeStartingProxy() throws {
        let port = proxyPort()
        let listeners = try portListeners(port: port)
        guard !listeners.isEmpty else {
            log("proxy port cleanup skipped; no listeners on port \(port)")
            return
        }

        let classified = classify(listeners)
        if proxyServiceLoaded(), !classified.ownedNginx.isEmpty {
            if classified.external.isEmpty {
                log("proxy port cleanup skipped; configured host proxy already owns port \(port)")
                return
            }
            try throwExternalListenerError(port: port, listeners: classified.external)
        }

        if !classified.ownedNginx.isEmpty {
            log("proxy port cleanup stopping owned nginx listeners port=\(port) pids=\(classified.ownedNginx.joined(separator: ","))")
            terminate(classified.ownedNginx, signal: "-TERM")
            sleep(1)
            let remainingOwned = classify(try portListeners(port: port)).ownedNginx
            if !remainingOwned.isEmpty {
                log("proxy port cleanup force stopping owned nginx listeners port=\(port) pids=\(remainingOwned.joined(separator: ","))")
                terminate(remainingOwned, signal: "-KILL")
                sleep(1)
            }
        }

        let remaining = try portListeners(port: port)
        guard remaining.isEmpty else {
            let classified = classify(remaining)
            if !classified.ownedNginx.isEmpty {
                let description = classified.ownedNginx.map { "nginx-\($0)" }.joined(separator: ",")
                log("proxy port cleanup could not stop owned listeners port=\(port) listeners=\(description)")
                throw LauncherError.runtimeOperationFailed(
                    "proxy port \(port) is still held by VitalServer nginx listener(s): \(description). Retry the update or repair Host proxy."
                )
            }
            try throwExternalListenerError(port: port, listeners: classified.external)
        }
        log("proxy port cleanup completed port=\(port)")
    }

    private func portListeners(port: Int) throws -> [PortListener] {
        let result = runProcess(Constants.Commands.lsof, ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"])
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stderr.isEmpty {
                return []
            }
            log("proxy port listener scan failed port=\(port) exitCode=\(result.exitCode) stderr=\(stderr)")
            throw LauncherError.runtimeOperationFailed(
                "failed to inspect proxy port \(port) listeners with lsof exitCode=\(result.exitCode)"
            )
        }
        return result.stdout
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count >= 2 else {
                    return nil
                }
                return PortListener(command: String(fields[0]), pid: String(fields[1]))
            }
    }

    private func classify(_ listeners: [PortListener]) -> (ownedNginx: [String], external: [PortListener]) {
        let expectedPID = expectedProxyNginxPID()
        var owned: [String] = []
        var external: [PortListener] = []

        for listener in listeners {
            guard listener.command == "nginx" else {
                external.append(listener)
                continue
            }
            if expectedPID.map({ $0 == listener.pid }) == true || commandLineOwnsProxy(listener.pid) {
                owned.append(listener.pid)
            } else {
                external.append(listener)
            }
        }
        return (Array(Set(owned)).sorted(), external)
    }

    private func commandLineOwnsProxy(_ pid: String) -> Bool {
        let result = runProcess(Constants.Commands.ps, ["-p", pid, "-o", "command="])
        guard result.exitCode == 0 else {
            return false
        }
        let commandLine = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandLine.isEmpty else {
            return false
        }
        return ownedNginxPathFragments.contains { fragment in
            !fragment.isEmpty && commandLine.contains(fragment)
        }
    }

    private func terminate(_ pids: [String], signal: String) {
        for pid in pids {
            _ = runProcess(Constants.Commands.kill, [signal, pid])
        }
    }

    private func throwExternalListenerError(port: Int, listeners: [PortListener]) throws -> Never {
        let description = listeners.map { "\($0.command)-\($0.pid)" }.joined(separator: ",")
        log("proxy port cleanup blocked by external listeners port=\(port) listeners=\(description)")
        throw LauncherError.runtimeOperationFailed(
            "proxy port \(port) is in use by external listener(s): \(description). Stop that process or change the Host proxy port."
        )
    }
}

private struct PortListener: Equatable {
    let command: String
    let pid: String
}
