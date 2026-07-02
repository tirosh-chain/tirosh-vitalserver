import Foundation
import Application
import Bootstrap
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
import Workflow
import Errors

extension RuntimeLifecycle {
    private static var missingRuntimeVersionValue: String { "missing-version" }
    private static var invalidRuntimeVersionValue: String { "invalid-version" }

    func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now)
    }

    func log(_ message: String) {
        print("[\(isoTimestamp())] \(message)")
    }

    func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: clock.now)
    }

    func runtimeVersionValue() -> String {
        switch runtimeVersionStore().readVersion() {
        case .loaded(let version):
            return version
        case .missing:
            return Self.missingRuntimeVersionValue
        case .failed(let reason):
            log("runtime version unavailable reason=invalid error=\(reason)")
            return Self.invalidRuntimeVersionValue
        }
    }

    func runtimeStatusValue() -> String? {
        switch statusReporter.loadStatusResult() {
        case .loaded(let document):
            document.status.rawValue
        case .missing, .failed:
            nil
        }
    }

    func runtimeObservedEventPublisher() -> RuntimeObservedEventPublisher {
        let healthUseCase = RefreshRuntimeHealthUseCase()
        return RuntimeObservedEventPublisher(
            previousStatus: {
                previousRuntimeStatus()
            },
            recordEvent: { status, previousStatus, operation, message, snapshot, eventType in
                try runtimeEventPublisher().recordObservedEvent(
                    status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    healthSnapshot: snapshot,
                    eventType: eventType
                )
            },
            recordEventBestEffort: { status, previousStatus, operation, message, snapshot, eventType in
                runtimeEventPublisher().recordObservedEventBestEffort(
                    status,
                    previousStatus: previousStatus,
                    operation: operation,
                    message: message,
                    healthSnapshot: snapshot,
                    eventType: eventType
                )
            },
            eventTypeForSnapshot: { snapshot, defaultEventType in
                healthUseCase.observedEventType(snapshot: snapshot, defaultEventType: defaultEventType)
            }
        )
    }

    private func previousRuntimeStatus() -> RuntimeStatusLevel? {
        switch statusReporter.loadStatusResult() {
        case .loaded(let document):
            return document.status
        case .missing:
            return nil
        case .failed(let reason):
            log("previous runtime status unavailable reason=\(reason)")
            return nil
        }
    }

    func runtimeEventPublisher() -> RuntimeEventPublisher {
        RuntimeEventPublisher(
            factory: runtimeEventFactory(),
            recorder: runtimeObservationRecorder()
        )
    }

    func runtimeObservationRecorder() -> RuntimeObservationRecorder {
        RuntimeObservationRecorder(
            eventRepository: CompositeRuntimeEventRepository(
                primary: JSONLRuntimeEventRepository(url: installedPaths.runtimeEvents),
                secondary: SQLiteRuntimeEventRepository(url: installedPaths.runtimeObservabilityDB),
                log: log
            ),
            log: log
        )
    }

    func runtimeEventFactory() -> RuntimeEventFactory {
        RuntimeEventFactory(
            timestamp: isoTimestamp,
            product: Constants.Product.identifier,
            runtimeVersion: runtimeVersionValue
        )
    }

    func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        let useCase = EvaluateRuntimeHealthUseCase()
        return useCase.snapshot(observation: useCase.observation(from: healthChecker.observationReads()))
    }

    func runtimeStatusWriter() -> RuntimeStatusWriter {
        RuntimeStatusWriterComposition.make(
            operations: RuntimeStatusWriterCompositionOperations(
                reporter: statusReporter,
                timestamp: isoTimestamp,
                runtimeVersion: runtimeVersionValue,
                healthSnapshot: runtimeHealthSnapshot,
                latestBackup: latestBackup
            )
        )
    }

    func runtimeObservedStatusPublisher() -> RuntimeObservedStatusPublisher {
        RuntimeObservedStatusPublisher(
            writeStatus: { status, operation, message, progress in
                try runtimeStatusWriter().writeStatus(
                    status,
                    operation: operation,
                    message: message,
                    progress: progress
                )
            }
        )
    }

    func writeRuntimeStatus(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        message: String,
        progress: RuntimeProgressDocument? = nil
    ) throws {
        try runtimeObservedStatusPublisher().publishStatus(
            status,
            operation: operation,
            message: message,
            progress: progress
        )
    }

    func writeRuntimeProgress(
        _ status: RuntimeStatusLevel,
        operation: RuntimeOperation,
        step: RuntimeWorkflowStep,
        stepStatus: RuntimeProgressStepStatus,
        phase: RuntimeProgressPhase,
        message: String,
        reasonCodes: [String] = []
    ) throws {
        let progress = RuntimeProgressDocument(
            operation: operation,
            phase: phase,
            step: step,
            stepStatus: stepStatus,
            message: message,
            reasonCodes: reasonCodes,
            startedAt: nil,
            updatedAt: isoTimestamp()
        )
        do {
            try runtimeStatusWriter().writeProgress(
                status,
                operation: operation,
                step: step,
                stepStatus: stepStatus,
                phase: phase,
                message: message,
                reasonCodes: reasonCodes
            )
        } catch {
            runtimeEventPublisher().recordProgressEventBestEffort(
                status: status,
                message: message,
                progress: progress
            )
            throw error
        }
        runtimeEventPublisher().recordProgressEventBestEffort(
            status: status,
            message: message,
            progress: progress
        )
    }
}
