import Contracts

public enum RuntimeHostProxyListenerPolicy {
    public static func failureReasons(
        port: Int,
        scanResult: RuntimeHostProxyListenerScanResult,
        expectedNginxPID: RuntimeProxyNginxPIDReadResult
    ) -> [RuntimeFailureReason] {
        switch scanResult {
        case .clear:
            return []
        case .unavailable:
            return [.hostProxyListenerScanUnavailable]
        case .inspectionFailed(let reason):
            return [.hostProxyListenerScanInspectionFailed(reason)]
        case .commandFailed(let exitCode, _), .malformedOutput(let exitCode, _):
            return [.hostProxyListenerScanFailed(port: port, exitCode: Int(exitCode))]
        case .loaded(let listeners):
            return loadedFailureReasons(
                port: port,
                listeners: listeners,
                expectedNginxPID: expectedNginxPID
            )
        }
    }

    private static func loadedFailureReasons(
        port: Int,
        listeners: [RuntimeHostProxyListener],
        expectedNginxPID: RuntimeProxyNginxPIDReadResult
    ) -> [RuntimeFailureReason] {
        guard !listeners.isEmpty else {
            return []
        }

        let joined = Array(listeners.map(\.hyphenDescription).prefix(5))
            .joined(separator: "_")
        switch expectedNginxPID {
        case .loaded(let expectedPID):
            let hasExpectedProxyNginx = listeners.contains {
                $0.command == "nginx" && $0.pid == expectedPID
            }
            return hasExpectedProxyNginx
                ? []
                : [.proxyPortInUse(port: port, listeners: joined)]
        case .missing, .empty:
            return [.hostProxyListenerMismatch(port: port, listeners: joined)]
        case .readFailed:
            return [
                .hostProxyConfigInvalid,
                .hostProxyListenerMismatch(port: port, listeners: joined),
            ]
        }
    }
}
