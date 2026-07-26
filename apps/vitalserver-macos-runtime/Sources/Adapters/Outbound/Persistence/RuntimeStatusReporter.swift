import Foundation
import Application
import Contracts
import Errors

public struct RuntimeStatusReporter {
    private let statusArtifactSink: RuntimeStatusArtifactSink
    private let progressArtifactSink: RuntimeProgressArtifactSink
    private let productIdentifier: String
    private let productRoot: URL
    private let runtimeHome: URL
    private let makeStatusDocument: (RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument
    private let makeProgressDocument: (RuntimeStatusProgressUpdateInput) -> RuntimeProgressDocument

    public init(
        statusArtifactSink: RuntimeStatusArtifactSink,
        progressArtifactSink: RuntimeProgressArtifactSink,
        productIdentifier: String,
        productRoot: URL,
        runtimeHome: URL,
        makeStatusDocument: @escaping (RuntimeStatusDocumentBuildInput) -> RuntimeStatusDocument,
        makeProgressDocument: @escaping (RuntimeStatusProgressUpdateInput) -> RuntimeProgressDocument
    ) {
        self.statusArtifactSink = statusArtifactSink
        self.progressArtifactSink = progressArtifactSink
        self.productIdentifier = productIdentifier
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
        self.makeStatusDocument = makeStatusDocument
        self.makeProgressDocument = makeProgressDocument
    }

    public func writeStatus(
        _ status: RuntimeStatusLevel,
        runtimeVersion: String,
        healthSnapshot: RuntimeHealthSnapshot,
        latestBackup: URL?
    ) throws {
        let document = makeStatusDocument(RuntimeStatusDocumentBuildInput(
            product: productIdentifier,
            status: status,
            productRoot: productRoot.path,
            runtimeHome: runtimeHome.path,
            runtimeVersion: runtimeVersion,
            healthSnapshot: healthSnapshot,
            latestBackup: latestBackup?.path
        ))
        try statusArtifactSink.save(document)
    }

    public func writeProgress(
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = [],
        updatedAt: String
    ) throws {
        let document = makeProgressDocument(RuntimeStatusProgressUpdateInput(
            operation: operation,
            step: step,
            stepStatus: stepStatus,
            phase: phase,
            message: message,
            reasonCodes: reasonCodes,
            updatedAt: updatedAt
        ))
        try progressArtifactSink.save(document)
    }
}
