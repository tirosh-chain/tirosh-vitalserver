import Contracts
import Domain
import Foundation

public struct RuntimeStatusDocumentBuildInput: Equatable {
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

public struct RuntimeStatusProgressUpdateInput: Equatable {
    public let operation: RuntimeOperation
    public let step: RuntimeWorkflowStep
    public let stepStatus: RuntimeProgressStepStatus
    public let phase: RuntimeProgressPhase
    public let message: String
    public let reasonCodes: [String]
    public let updatedAt: String

    public init(
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String],
        updatedAt: String
    ) {
        self.operation = operation
        self.step = step
        self.stepStatus = stepStatus
        self.phase = phase
        self.message = message
        self.reasonCodes = reasonCodes
        self.updatedAt = updatedAt
    }
}

public struct BuildRuntimeStatusDocumentUseCase {
    public init() {}

    public func build(_ input: RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument {
        RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: input.product,
            status: input.status,
            productRoot: input.productRoot,
            runtimeHome: input.runtimeHome,
            runtimeVersion: input.runtimeVersion,
            healthSnapshot: input.healthSnapshot,
            latestBackup: input.latestBackup
        ))
    }

    public func progressDocument(_ input: RuntimeStatusProgressUpdateInput) -> RuntimeProgressDocument {
        RuntimeProgressDocument(
            operation: input.operation,
            phase: input.phase,
            step: input.step,
            stepStatus: input.stepStatus,
            message: input.message,
            reasonCodes: input.reasonCodes,
            startedAt: nil,
            updatedAt: input.updatedAt
        )
    }
}
