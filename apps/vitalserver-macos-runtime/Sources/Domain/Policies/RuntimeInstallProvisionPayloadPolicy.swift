import Contracts

public enum RuntimeInstallProvisionPayloadPolicy {
    public static func document(
        artifactStates: [RuntimeInstallArtifactState]
    ) -> RuntimeInstallProvisionPayloadDocument {
        let blockers = artifactBlockers(artifactStates)
        return RuntimeInstallProvisionPayloadDocument(
            passed: blockers.isEmpty,
            blockers: blockers,
            artifactStates: artifactStates
        )
    }

    public static func artifactBlockers(_ states: [RuntimeInstallArtifactState]) -> [String] {
        states.compactMap { state in
            switch state {
            case .absent(let path):
                return "install-payload-missing:path=\(path)"
            case .inspectFailed(let path, let reason):
                return "install-payload-inspect-failed:path=\(path) reason=\(reason)"
            case .unknown(let value):
                return "install-payload-state-unknown:value=\(value)"
            case .present:
                return nil
            }
        }
    }
}
