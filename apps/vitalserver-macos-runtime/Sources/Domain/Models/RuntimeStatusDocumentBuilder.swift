import Contracts
public struct RuntimeStatusDocumentInput: Equatable {
    public let product: String
    public let status: RuntimeStatusLevel
    public let productRoot: String
    public let runtimeHome: String
    public let runtimeVersion: String
    public let healthSnapshot: RuntimeHealthSnapshot
    public let latestBackup: String?

    public init(
        product: String,
        status: RuntimeStatusLevel,
        productRoot: String,
        runtimeHome: String,
        runtimeVersion: String,
        healthSnapshot: RuntimeHealthSnapshot,
        latestBackup: String?
    ) {
        self.product = product
        self.status = status
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
        self.runtimeVersion = runtimeVersion
        self.healthSnapshot = healthSnapshot
        self.latestBackup = latestBackup
    }
}

public enum RuntimeStatusDocumentBuilder {
    public static func build(_ input: RuntimeStatusDocumentInput) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            schemaVersion: 2,
            product: input.product,
            status: input.status,
            productRoot: input.productRoot,
            runtimeHome: input.runtimeHome,
            runtimeVersion: input.runtimeVersion,
            vmService: input.healthSnapshot.vmService,
            proxyService: input.healthSnapshot.proxyService,
            watchdogService: input.healthSnapshot.watchdogService,
            guestAddressRead: input.healthSnapshot.guestAddressRead,
            vmIP: input.healthSnapshot.vmIP,
            proxyPort: input.healthSnapshot.proxyPort,
            proxyPortReadState: input.healthSnapshot.proxyPortReadState,
            hostProxyHTTP: input.healthSnapshot.hostProxyHTTP,
            guestHTTP: input.healthSnapshot.guestHTTP,
            redisUIHTTP: input.healthSnapshot.redisUIHTTP,
            swaggerUIHTTP: input.healthSnapshot.swaggerUIHTTP,
            rootfsBase: input.healthSnapshot.rootfsBase,
            vmDisk: input.healthSnapshot.vmDisk,
            latestBackup: input.latestBackup
        )
    }
}
