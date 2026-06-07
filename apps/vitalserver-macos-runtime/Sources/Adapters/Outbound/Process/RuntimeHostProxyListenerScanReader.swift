import Application
import Contracts
import Foundation
import Errors

public struct RuntimeHostProxyListenerScanReader {
    private let lsofPath: String
    private let fileStore: RuntimeFileStore
    private let commandRunner: RuntimeCommandRunner

    public init(
        lsofPath: String,
        fileStore: RuntimeFileStore,
        commandRunner: RuntimeCommandRunner
    ) {
        self.lsofPath = lsofPath
        self.fileStore = fileStore
        self.commandRunner = commandRunner
    }

    public func read(port: Int) -> RuntimeHostProxyListenerScanResult {
        switch fileStore.fileState(atPath: lsofPath) {
        case .executable:
            break
        case .inspectFailed(let reason):
            return .inspectionFailed("path=\(lsofPath) reason=\(reason)")
        case .missing:
            return .unavailable
        case .present:
            return .inspectionFailed("path=\(lsofPath) reason=not executable")
        case .unknown(let state):
            return .inspectionFailed("path=\(lsofPath) reason=unknown file state \(state)")
        }

        let result = commandRunner.run(
            lsofPath,
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        )
        return RuntimeHostProxyListenerScanResultMapper.scanResult(from: result)
    }
}
