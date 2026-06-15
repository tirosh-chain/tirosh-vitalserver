import Application
import Contracts
import Foundation
import Errors

public struct RuntimeInstalledProxyPortReader {
    private let plistBuddyPath: String
    private let proxyLaunchDaemonPlist: String
    private let fileStore: RuntimeFileStore
    private let commandRunner: RuntimeCommandRunner

    public init(
        plistBuddyPath: String,
        proxyLaunchDaemonPlist: String,
        fileStore: RuntimeFileStore,
        commandRunner: RuntimeCommandRunner
    ) {
        self.plistBuddyPath = plistBuddyPath
        self.proxyLaunchDaemonPlist = proxyLaunchDaemonPlist
        self.fileStore = fileStore
        self.commandRunner = commandRunner
    }

    public func read() -> RuntimeProxyPortReadState {
        let result = commandRunner.run(
            plistBuddyPath,
            arguments: [
                "-c",
                "Print :EnvironmentVariables:VITALSERVER_PROXY_PORT",
                proxyLaunchDaemonPlist,
            ]
        )
        if result.exitCode != 0 {
            return failedReadState(result)
        }
        return loadedReadState(result)
    }

    private func failedReadState(_ result: RuntimeProcessResult) -> RuntimeProxyPortReadState {
        let reason = RuntimeProcessFailureMessageFormatter.message(result)
        let plistURL = URL(fileURLWithPath: proxyLaunchDaemonPlist)
        let plistState = fileStore.pathState(at: plistURL)
        switch plistState {
        case .file:
            return .commandFailed(exitCode: result.exitCode, reason: reason)
        case .missing:
            return .missing("proxy launchd plist missing path=\(plistURL.path)")
        case .inspectFailed(let inspectionReason):
            return .commandFailed(
                exitCode: result.exitCode,
                reason: "\(reason) plistPathInspectionFailed path=\(plistURL.path) reason=\(inspectionReason)"
            )
        case .directory, .other, .unknown:
            return .commandFailed(
                exitCode: result.exitCode,
                reason: "\(reason) plistPathStateUnexpected path=\(plistURL.path) state=\(plistState.rawValue)"
            )
        }
    }

    private func loadedReadState(_ result: RuntimeProcessResult) -> RuntimeProxyPortReadState {
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            return .commandFailed(
                exitCode: result.exitCode,
                reason: RuntimeProcessFailureMessageFormatter.message(result)
            )
        }
        guard !value.isEmpty else {
            return stderr.isEmpty ? .empty : .invalid(stderr)
        }
        guard let port = Int(value) else {
            return .invalid(value)
        }
        guard (1...65_535).contains(port) else {
            return .outOfRange(port)
        }
        return .loaded(port)
    }
}

public struct RuntimeProxyNginxPIDReader {
    private let url: URL
    private let fileStore: RuntimeFileStore

    public init(url: URL, fileStore: RuntimeFileStore) {
        self.url = url
        self.fileStore = fileStore
    }

    public func read() -> RuntimeProxyNginxPIDReadResult {
        let pathState = fileStore.pathState(at: url)
        switch pathState {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .readFailed("proxy nginx PID path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .readFailed("proxy nginx PID path state is unexpected path=\(url.path) state=\(pathState.rawValue)")
        }
        do {
            let value = try fileStore.readUTF8Text(url)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return .empty
            }
            return .loaded(value)
        } catch {
            return .readFailed(String(describing: error))
        }
    }
}
