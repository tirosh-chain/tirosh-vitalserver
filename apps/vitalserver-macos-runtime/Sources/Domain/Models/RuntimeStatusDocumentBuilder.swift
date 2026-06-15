import Contracts
public struct RuntimeStatusDocumentInput: Equatable {
    public let product: String
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let message: String
    public let updatedAt: String
    public let productRoot: String
    public let runtimeHome: String
    public let runtimeVersion: String
    public let healthSnapshot: RuntimeHealthSnapshot
    public let latestBackup: String?
    public let progress: RuntimeProgressDocument?

    public init(
        product: String,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        updatedAt: String,
        productRoot: String,
        runtimeHome: String,
        runtimeVersion: String,
        healthSnapshot: RuntimeHealthSnapshot,
        latestBackup: String?,
        progress: RuntimeProgressDocument? = nil
    ) {
        self.product = product
        self.status = status
        self.operation = operation
        self.message = message
        self.updatedAt = updatedAt
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
        self.runtimeVersion = runtimeVersion
        self.healthSnapshot = healthSnapshot
        self.latestBackup = latestBackup
        self.progress = progress
    }
}

public enum RuntimeStatusDocumentBuilder {
    public static func build(_ input: RuntimeStatusDocumentInput) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            schemaVersion: 2,
            product: input.product,
            status: input.status,
            operation: input.operation,
            message: input.message,
            updatedAt: input.updatedAt,
            productRoot: input.productRoot,
            runtimeHome: input.runtimeHome,
            runtimeVersion: input.runtimeVersion,
            vmService: input.healthSnapshot.vmService,
            proxyService: input.healthSnapshot.proxyService,
            watchdogService: input.healthSnapshot.watchdogService,
            vmState: input.healthSnapshot.vmState,
            vmErrors: input.healthSnapshot.vmErrors,
            vmIP: input.healthSnapshot.vmIP,
            proxyPort: input.healthSnapshot.proxyPort,
            proxyPortReadState: input.healthSnapshot.proxyPortReadState,
            hostProxyHTTP: input.healthSnapshot.hostProxyHTTP,
            guestHTTP: input.healthSnapshot.guestHTTP,
            redisUIHTTP: input.healthSnapshot.redisUIHTTP,
            swaggerUIHTTP: input.healthSnapshot.swaggerUIHTTP,
            rootfsBase: input.healthSnapshot.rootfsBase,
            vmDisk: input.healthSnapshot.vmDisk,
            failureReasons: RuntimeStatusFailureReasonPolicy.failureReasons(
                status: input.status,
                snapshot: input.healthSnapshot
            ),
            latestBackup: input.latestBackup,
            progress: input.progress,
            containerObservation: input.healthSnapshot.containerObservation,
            vitalDBObservation: input.healthSnapshot.vitalDBObservation
        )
    }
}
