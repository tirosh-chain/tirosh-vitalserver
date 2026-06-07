import Contracts
import Domain

public struct FreshInstallPreflightOperations {
    public var settingsState: () -> RuntimeInstallSettingsState
    public var settingsDefaultProxyPort: Int?
    public var artifactStates: () -> [RuntimeInstallArtifactState]
    public var serviceStates: () -> [RuntimeFreshInstallServiceState]
    public var packageReceiptStates: () -> [RuntimePackageReceiptState]
    public var proxyPortState: (Int) -> RuntimeHostProxyPortState

    public init(
        settingsState: @escaping () -> RuntimeInstallSettingsState,
        settingsDefaultProxyPort: Int? = nil,
        artifactStates: @escaping () -> [RuntimeInstallArtifactState],
        serviceStates: @escaping () -> [RuntimeFreshInstallServiceState],
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        proxyPortState: @escaping (Int) -> RuntimeHostProxyPortState
    ) {
        self.settingsState = settingsState
        self.settingsDefaultProxyPort = settingsDefaultProxyPort
        self.artifactStates = artifactStates
        self.serviceStates = serviceStates
        self.packageReceiptStates = packageReceiptStates
        self.proxyPortState = proxyPortState
    }
}

public struct FreshInstallPreflightUseCase {
    public init() {}

    public func run(operations: FreshInstallPreflightOperations) -> RuntimeFreshInstallPreflightDocument {
        let settings = RuntimeInstallSettingsDefaultApplicator.apply(
            operations.settingsState(),
            defaultProxyPort: operations.settingsDefaultProxyPort
        )
        let proxyState = settings.proxyPort.map(operations.proxyPortState)
        return RuntimeFreshInstallPreflightPolicy.document(input: RuntimeFreshInstallPreflightInput(
            settingsState: settings,
            artifactStates: operations.artifactStates(),
            serviceStates: operations.serviceStates(),
            packageReceiptStates: operations.packageReceiptStates(),
            proxyPortState: proxyState
        ))
    }
}

public enum RuntimeInstallSettingsDefaultApplicator {
    public static func apply(
        _ state: RuntimeInstallSettingsState,
        defaultProxyPort: Int?
    ) -> RuntimeInstallSettingsState {
        guard let defaultProxyPort else {
            return state
        }

        switch state {
        case .missing(let path), .proxyPortMissing(let path):
            guard (1...65_535).contains(defaultProxyPort) else {
                return .invalid(path: path, reason: "default proxyPort out of range value=\(defaultProxyPort)")
            }
            return .defaulted(path: path, proxyPort: defaultProxyPort)
        case .defaulted, .loaded, .readFailed, .invalid, .unknown:
            return state
        }
    }
}
