import Contracts

public struct FreshInstallPreflightOperations {
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
}

public struct FreshInstallPreflightUseCase {
    public init() {}

    public func run(operations: FreshInstallPreflightOperations) -> RuntimeFreshInstallPreflightDocument {
        let settings = operations.settingsState()
        let proxyState = settings.proxyPort.map(operations.proxyPortState)
        return InstallRuntimeUseCase().freshInstallPreflightDocument(
            settingsState: settings,
            artifactStates: operations.artifactStates(),
            serviceStates: operations.serviceStates(),
            packageReceiptStates: operations.packageReceiptStates(),
            proxyPortState: proxyState
        )
    }
}
