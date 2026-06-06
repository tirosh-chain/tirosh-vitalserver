import Contracts
import Domain
import Errors

public struct RuntimeFreshInstallPreflightRunner {
    public var settingsState: () -> RuntimeInstallSettingsState
    public var artifactStates: () -> [RuntimeInstallArtifactState]
    public var serviceStates: () -> [RuntimeFreshInstallServiceState]
    public var packageReceiptStates: () -> [RuntimePackageReceiptState]
    public var proxyPortState: (Int) -> RuntimeHostProxyPortState

    public init(
        settingsState: @escaping () -> RuntimeInstallSettingsState,
        artifactStates: @escaping () -> [RuntimeInstallArtifactState],
        serviceStates: @escaping () -> [RuntimeFreshInstallServiceState],
        packageReceiptStates: @escaping () -> [RuntimePackageReceiptState],
        proxyPortState: @escaping (Int) -> RuntimeHostProxyPortState
    ) {
        self.settingsState = settingsState
        self.artifactStates = artifactStates
        self.serviceStates = serviceStates
        self.packageReceiptStates = packageReceiptStates
        self.proxyPortState = proxyPortState
    }

    public func run() -> RuntimeFreshInstallPreflightDocument {
        let settings = settingsState()
        let proxyState = settings.proxyPort.map(proxyPortState)
        return RuntimeFreshInstallPreflightPolicy.document(input: RuntimeFreshInstallPreflightInput(
            settingsState: settings,
            artifactStates: artifactStates(),
            serviceStates: serviceStates(),
            packageReceiptStates: packageReceiptStates(),
            proxyPortState: proxyState
        ))
    }
}
