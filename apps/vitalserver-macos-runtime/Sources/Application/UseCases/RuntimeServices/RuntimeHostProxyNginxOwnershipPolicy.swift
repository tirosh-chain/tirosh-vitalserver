import Contracts
import Foundation

public enum RuntimeHostProxyNginxOwnershipPolicyDecision: Equatable, Sendable {
    case classified(RuntimeHostProxyListenerClassification)
    case commandLineReadMissing(pid: String)
    case commandLineReadFailed(pid: String, reason: String)
    case commandLineEmpty(pid: String)
}

public enum RuntimeHostProxyNginxOwnershipPolicy {
    public static func classify(
        listeners: [RuntimeHostProxyListener],
        expectedPID: String?,
        ownedNginxPathFragments: [String],
        commandLineReadResults: [String: RuntimeHostProxyNginxCommandLineReadResult]
    ) -> RuntimeHostProxyNginxOwnershipPolicyDecision {
        var owned: Set<String> = []
        var external: [RuntimeHostProxyListener] = []
        let ownedFragments = ownedNginxPathFragments.filter { !$0.isEmpty }

        for listener in listeners {
            guard listener.command == "nginx" else {
                external.append(listener)
                continue
            }
            if expectedPID == listener.pid {
                owned.insert(listener.pid)
                continue
            }
            guard let commandLineResult = commandLineReadResults[listener.pid] else {
                return .commandLineReadMissing(pid: listener.pid)
            }
            switch commandLineResult {
            case .loaded(let commandLine):
                let trimmedCommandLine = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedCommandLine.isEmpty else {
                    return .commandLineEmpty(pid: listener.pid)
                }
                if ownedFragments.contains(where: { trimmedCommandLine.contains($0) }) {
                    owned.insert(listener.pid)
                } else {
                    external.append(listener)
                }
            case .empty:
                return .commandLineEmpty(pid: listener.pid)
            case .readFailed(let reason):
                return .commandLineReadFailed(pid: listener.pid, reason: reason)
            }
        }

        return .classified(
            RuntimeHostProxyListenerClassification(
                ownedNginx: Array(owned).sorted(),
                external: external
            )
        )
    }
}
