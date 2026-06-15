import Foundation
import Application
import Contracts
import Errors

public struct RuntimeStatusReporter {
    private let repository: RuntimeStatusRepository
    private let productIdentifier: String
    private let productRoot: URL
    private let runtimeHome: URL
    private let makeStatusDocument: (RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument
    private let makeProgressDocument: (RuntimeStatusProgressUpdateInput) -> RuntimeStatusDocument

    public init(
        repository: RuntimeStatusRepository,
        productIdentifier: String,
        productRoot: URL,
        runtimeHome: URL,
        makeStatusDocument: @escaping (RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument,
        makeProgressDocument: @escaping (RuntimeStatusProgressUpdateInput) -> RuntimeStatusDocument
    ) {
        self.repository = repository
        self.productIdentifier = productIdentifier
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
        self.makeStatusDocument = makeStatusDocument
        self.makeProgressDocument = makeProgressDocument
    }

    public func loadStatusResult() -> RuntimeStatusDocumentLoadResult {
        repository.loadResult()
    }

    public func writeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        updatedAt: String,
        runtimeVersion: String,
        healthSnapshot: RuntimeHealthSnapshot,
        latestBackup: URL?,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        let document = makeStatusDocument(RuntimeStatusDocumentBuildInput(
            product: productIdentifier,
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

    public func writeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = [],
        updatedAt: String,
        runtimeVersion: String,
        latestBackup: URL?
    ) throws {
        let current: RuntimeStatusDocument
        switch repository.loadResult() {
        case .loaded(let document):
            current = document
        case .missing:
            throw RuntimeStatusReporterError.missingStatusDocumentForProgress
        case .failed(let message):
            throw RuntimeStatusReporterError.statusDocumentReadFailed(message)
        }
        let document = makeProgressDocument(RuntimeStatusProgressUpdateInput(
            current: current,
            status: status,
            operation: operation,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: updatedAt,
            runtimeVersion: runtimeVersion,
            latestBackup: latestBackup?.path
        ))
        try repository.save(document)
    }
}
