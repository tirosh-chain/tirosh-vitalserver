import Foundation
import RuntimeCore

struct RuntimeStatusReporter {
    private let repository: RuntimeStatusRepository
    private let productRoot: URL
    private let runtimeHome: URL

    init(
        repository: RuntimeStatusRepository,
        productRoot: URL,
        runtimeHome: URL
    ) {
        self.repository = repository
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
    }

    func statusValue() -> String {
        repository.load()?.status.rawValue ?? "unknown"
    }

    func writeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        updatedAt: String,
        runtimeVersion: String,
        healthSnapshot: RuntimeHealthSnapshot,
        latestBackup: URL?,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
            product: Constants.Product.identifier,
            status: status,
            operation: operation,
            message: message,
            updatedAt: updatedAt,
            productRoot: productRoot.path,
            runtimeHome: runtimeHome.path,
            runtimeVersion: runtimeVersion,
            healthSnapshot: healthSnapshot,
            latestBackup: latestBackup?.path,
            progress: progress
        ))
        try repository.save(document)
    }

    func writeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = [],
        updatedAt: String,
        runtimeVersion: String,
        healthSnapshot: RuntimeHealthSnapshot,
        latestBackup: URL?
    ) throws {
        try writeStatus(
            status,
            operation: operation,
            message: message,
            updatedAt: updatedAt,
            runtimeVersion: runtimeVersion,
            healthSnapshot: healthSnapshot,
            latestBackup: latestBackup,
            progress: RuntimeProgressDocument(
                operation: operation,
                phase: phase,
                step: step,
                stepStatus: stepStatus,
                message: message,
                reasonCodes: reasonCodes,
                startedAt: nil,
                updatedAt: updatedAt
            )
        )
    }
}
