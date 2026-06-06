import Contracts
import Foundation
import Errors

public struct RuntimeFreshInstallPreflightInput: Equatable, Sendable {
    public let settingsState: RuntimeInstallSettingsState
    public let artifactStates: [RuntimeInstallArtifactState]
    public let serviceStates: [RuntimeFreshInstallServiceState]
    public let packageReceiptStates: [RuntimePackageReceiptState]
    public let proxyPortState: RuntimeHostProxyPortState?

    public init(
        settingsState: RuntimeInstallSettingsState,
        artifactStates: [RuntimeInstallArtifactState],
        serviceStates: [RuntimeFreshInstallServiceState],
        packageReceiptStates: [RuntimePackageReceiptState],
        proxyPortState: RuntimeHostProxyPortState?
    ) {
        self.settingsState = settingsState
        self.artifactStates = artifactStates
        self.serviceStates = serviceStates
        self.packageReceiptStates = packageReceiptStates
        self.proxyPortState = proxyPortState
    }
}

public enum RuntimeFreshInstallPreflightPolicy {
    public static func document(input: RuntimeFreshInstallPreflightInput) -> RuntimeFreshInstallPreflightDocument {
        let blockers = blockers(input: input)
        return RuntimeFreshInstallPreflightDocument(
            passed: blockers.isEmpty,
            proxyPort: input.settingsState.proxyPort,
            blockers: blockers,
            settingsState: input.settingsState,
            artifactStates: input.artifactStates,
            serviceStates: input.serviceStates,
            packageReceiptStates: input.packageReceiptStates,
            proxyPortState: input.proxyPortState
        )
    }

    public static func blockers(input: RuntimeFreshInstallPreflightInput) -> [String] {
        var blockers: [String] = []
        blockers.append(contentsOf: settingsBlockers(input.settingsState))
        blockers.append(contentsOf: artifactBlockers(input.artifactStates))
        blockers.append(contentsOf: serviceBlockers(input.serviceStates))
        blockers.append(contentsOf: RuntimeUninstallReadinessPolicy.packageReceiptBlockers(input.packageReceiptStates))
        blockers.append(contentsOf: proxyPortBlockers(input.proxyPortState, expectedPort: input.settingsState.proxyPort))
        return blockers
    }

    private static func settingsBlockers(_ state: RuntimeInstallSettingsState) -> [String] {
        switch state {
        case .readFailed(let path, let reason):
            return ["install-settings-read-failed:path=\(path) reason=\(reason)"]
        case .invalid(let path, let reason):
            return ["install-settings-invalid:path=\(path) reason=\(reason)"]
        case .unknown(let value):
            return ["install-settings-state-unknown:value=\(value)"]
        case .defaulted, .loaded:
            return []
        }
    }

    private static func artifactBlockers(_ states: [RuntimeInstallArtifactState]) -> [String] {
        states.compactMap { state in
            switch state {
            case .present(let path):
                return "install-artifact-present:path=\(path)"
            case .inspectFailed(let path, let reason):
                return "install-artifact-inspect-failed:path=\(path) reason=\(reason)"
            case .unknown(let value):
                return "install-artifact-state-unknown:value=\(value)"
            case .absent:
                return nil
            }
        }
    }

    private static func serviceBlockers(_ states: [RuntimeFreshInstallServiceState]) -> [String] {
        var blockers: [String] = []
        for service in RuntimeManagedService.stopOrder {
            guard let state = states.first(where: { $0.label == service.label })?.state else {
                blockers.append("launchd-service-state-missing:label=\(service.label)")
                continue
            }
            switch state {
            case .loaded:
                blockers.append("launchd-service-loaded:label=\(service.label)")
            case .readFailed(let reason):
                blockers.append("launchd-service-read-failed:label=\(service.label) reason=\(reason)")
            case .permissionDenied(let reason):
                blockers.append("launchd-service-permission-denied:label=\(service.label) reason=\(reason)")
            case .unknown(let value):
                blockers.append("launchd-service-state-unknown:label=\(service.label) value=\(value)")
            case .notLoaded:
                continue
            }
        }
        return blockers
    }

    private static func proxyPortBlockers(
        _ state: RuntimeHostProxyPortState?,
        expectedPort: Int?
    ) -> [String] {
        guard let state else {
            if let expectedPort {
                return ["host-proxy-port-state-missing:port=\(expectedPort)"]
            }
            return []
        }
        switch state {
        case .occupied(let port, let listeners):
            return ["host-proxy-port-occupied:port=\(port) listeners=\(listeners)"]
        case .inspectFailed(let port, let reason):
            return ["host-proxy-port-inspect-failed:port=\(port) reason=\(reason)"]
        case .unknown(let value):
            return ["host-proxy-port-state-unknown:value=\(value)"]
        case .clear:
            return []
        }
    }
}
