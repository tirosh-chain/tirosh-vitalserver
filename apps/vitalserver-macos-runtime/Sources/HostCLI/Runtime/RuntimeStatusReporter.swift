import Foundation
import Core
import Contracts

struct RuntimeStatusReporter {
    private let repository: RuntimeStatusRepository
    private let eventRepository: RuntimeEventRepository?
    private let productRoot: URL
    private let runtimeHome: URL
    private let eventID: () -> String

    init(
        repository: RuntimeStatusRepository,
        eventRepository: RuntimeEventRepository? = nil,
        productRoot: URL,
        runtimeHome: URL,
        eventID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.repository = repository
        self.eventRepository = eventRepository
        self.productRoot = productRoot
        self.runtimeHome = runtimeHome
        self.eventID = eventID
    }

    func statusValue() -> String {
        repository.load()?.status.rawValue ?? "unknown"
    }

    func loadStatus() -> RuntimeStatusDocument? {
        repository.load()
    }

    func recentEvents(limit: Int) -> [RuntimeEventDocument] {
        eventRepository?.recent(limit: limit) ?? []
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
        let previous = repository.load()
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
        try eventRepository?.append(RuntimeEventDocument(
            id: eventID(),
            eventType: progress == nil ? .statusChanged : .progressUpdated,
            timestamp: updatedAt,
            product: document.product,
            status: document.status,
            previousStatus: previous?.status,
            operation: document.operation,
            message: document.message,
            runtimeVersion: document.runtimeVersion,
            failureReasons: document.failureReasons,
            progress: document.progress
        ))
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
