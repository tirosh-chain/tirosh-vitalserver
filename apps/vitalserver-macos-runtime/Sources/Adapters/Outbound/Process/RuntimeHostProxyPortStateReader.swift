import Application
import Contracts
import Foundation

public enum RuntimeHostProxyPortStateReader {
    public static func state(
        port: Int,
        lsofPath: String,
        fileStore: RuntimeFileStore,
        commandRunner: RuntimeCommandRunner
    ) -> RuntimeHostProxyPortState {
        let scan = RuntimeHostProxyListenerScanReader(
            lsofPath: lsofPath,
            fileStore: fileStore,
            commandRunner: commandRunner
        ).read(port: port)
        return state(port: port, scan: scan)
    }

    static func state(
        port: Int,
        scan: RuntimeHostProxyListenerScanResult
    ) -> RuntimeHostProxyPortState {
        switch scan {
        case .clear:
            return .clear(port: port)
        case .loaded(let listeners):
            return .occupied(
                port: port,
                listeners: listeners.map(\.slashDescription).sorted().joined(separator: ",")
            )
        case .unavailable:
            return .inspectFailed(port: port, reason: "lsof unavailable")
        case .inspectionFailed(let reason):
            return .inspectFailed(port: port, reason: reason)
        case .commandFailed(_, let reason), .malformedOutput(_, let reason):
            return .inspectFailed(port: port, reason: reason)
        }
    }
}
