import Contracts
import Domain
import Foundation

public struct RuntimeStatusDocumentBuildInput: Equatable {
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

public struct RuntimeStatusProgressUpdateInput: Equatable {
    public let current: RuntimeStatusDocument
    public let status: RuntimeStatusLevel
    public let operation: RuntimeOperation
    public let step: RuntimeWorkflowStep
    public let stepStatus: RuntimeProgressStepStatus
    public let phase: RuntimeProgressPhase
    public let message: String
    public let reasonCodes: [String]
    public let updatedAt: String
    public let runtimeVersion: String
    public let latestBackup: String?

    public init(
        current: RuntimeStatusDocument,
        status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String],
        updatedAt: String,
        runtimeVersion: String,
        latestBackup: String?
    ) {
        self.current = current
        self.status = status
        self.operation = operation
        self.step = step
        self.stepStatus = stepStatus
        self.phase = phase
        self.message = message
        self.reasonCodes = reasonCodes
        self.updatedAt = updatedAt
        self.runtimeVersion = runtimeVersion
        self.latestBackup = latestBackup
    }
}

public struct BuildRuntimeStatusDocumentUseCase {
    public init() {}

    public func build(_ input: RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument {
        RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: input.product,
            status: input.status,
            operation: input.operation,
            message: input.message,
            updatedAt: input.updatedAt,
            productRoot: input.productRoot,
            runtimeHome: input.runtimeHome,
            runtimeVersion: input.runtimeVersion,
            healthSnapshot: input.healthSnapshot,
            latestBackup: input.latestBackup,
            progress: input.progress
        ))
    }

    public func progressUpdate(_ input: RuntimeStatusProgressUpdateInput) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            schemaVersion: input.current.schemaVersion,
            product: input.current.product,
            status: input.status,
            operation: input.operation,
            message: input.message,
            updatedAt: input.updatedAt,
            productRoot: input.current.productRoot,
            runtimeHome: input.current.runtimeHome,
            runtimeVersion: input.runtimeVersion,
            vmService: input.current.vmService,
            proxyService: input.current.proxyService,
            watchdogService: input.current.watchdogService,
            vmState: input.current.vmState,
            vmErrors: input.current.vmErrors,
            vmIP: input.current.vmIP,
            proxyPort: input.current.proxyPort,
            hostProxyHTTP: input.current.hostProxyHTTP,
            guestHTTP: input.current.guestHTTP,
            redisUIHTTP: input.current.redisUIHTTP,
            swaggerUIHTTP: input.current.swaggerUIHTTP,
            rootfsBase: input.current.rootfsBase,
            vmDisk: input.current.vmDisk,
            failureReasons: input.current.failureReasons,
            domainErrors: input.current.domainErrors,
            latestBackup: input.latestBackup,
            progress: RuntimeProgressDocument(
                operation: input.operation,
                phase: input.phase,
                step: input.step,
                stepStatus: input.stepStatus,
                message: input.message,
                reasonCodes: input.reasonCodes,
                startedAt: nil,
                updatedAt: input.updatedAt
            ),
            containerObservation: input.current.containerObservation,
            vitalDBObservation: input.current.vitalDBObservation
        )
    }
}
