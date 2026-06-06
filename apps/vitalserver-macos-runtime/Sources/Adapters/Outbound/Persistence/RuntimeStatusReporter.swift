import Foundation
import Application
import Contracts
import Domain
import Errors

public struct RuntimeStatusReporter {
    private let repository: RuntimeStatusRepository
    private let productIdentifier: String
    private let productRoot: URL
    private let runtimeHome: URL

    public init(
        repository: RuntimeStatusRepository,
        productIdentifier: String,
        productRoot: URL,
        runtimeHome: URL
    ) {
        self.repository = repository
        self.productIdentifier = productIdentifier
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
    }

    public func statusValue() -> String? {
        loadStatus()?.status.rawValue
    }

    public func loadStatusResult() -> RuntimeStatusDocumentLoadResult {
        repository.loadResult()
    }

    public func loadStatus() -> RuntimeStatusDocument? {
        guard case .loaded(let document) = repository.loadResult() else {
            return nil
        }
        return document
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
        let document = RuntimeStatusDocumentBuilder.build(RuntimeStatusDocumentInput(
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
        let document = RuntimeStatusDocument(
            schemaVersion: current.schemaVersion,
            product: current.product,
            status: status,
            operation: operation,
            message: message,
            updatedAt: updatedAt,
            productRoot: current.productRoot,
            runtimeHome: current.runtimeHome,
            runtimeVersion: runtimeVersion,
            vmService: current.vmService,
            proxyService: current.proxyService,
            watchdogService: current.watchdogService,
            vmState: current.vmState,
            vmErrors: current.vmErrors,
            vmIP: current.vmIP,
            proxyPort: current.proxyPort,
            hostProxyHTTP: current.hostProxyHTTP,
            guestHTTP: current.guestHTTP,
            redisUIHTTP: current.redisUIHTTP,
            swaggerUIHTTP: current.swaggerUIHTTP,
            rootfsBase: current.rootfsBase,
            vmDisk: current.vmDisk,
            failureReasons: current.failureReasons,
            domainErrors: current.domainErrors,
            latestBackup: latestBackup?.path ?? current.latestBackup,
            progress: RuntimeProgressDocument(
                operation: operation,
                phase: phase,
                step: step,
                stepStatus: stepStatus,
                message: message,
                reasonCodes: reasonCodes,
                startedAt: nil,
                updatedAt: updatedAt
            ),
            containerObservation: current.containerObservation,
            vitalDBObservation: current.vitalDBObservation
        )
        try repository.save(document)
    }
}
