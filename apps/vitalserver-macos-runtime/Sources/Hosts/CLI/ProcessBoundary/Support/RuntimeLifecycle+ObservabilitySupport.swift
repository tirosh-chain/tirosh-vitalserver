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
            return RuntimeVersionStore.missingVersionValue
        case .failed(let reason):
            log("runtime version unavailable reason=invalid error=\(reason)")
            return RuntimeVersionStore.invalidVersionValue
        }
    }

    func runtimeStatusValue() -> String? {
        statusReporter.statusValue()
    }

    func runtimeObservedEventPublisher() -> RuntimeObservedEventPublisher {
        RuntimeObservedEventPublisher(
            previousStatus: {
                statusReporter.loadStatus()?.status
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
            }
        )
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

    func vitalDBObservationProjector() -> RuntimeVitalDBObservationProjector {
        RuntimeVitalDBObservationProjector(
            appendObservation: { observation in
                try SQLiteVitalDBObservationRepository(url: installedPaths.runtimeObservabilityDB).append(observation)
            },
            log: log
        )
    }

    func projectVitalDBObservationBestEffort(_ observation: VitalDBObservationDocument) {
        vitalDBObservationProjector().projectBestEffort(observation)
    }

    func runtimeHealthSnapshot() -> RuntimeHealthSnapshot {
        healthChecker.snapshot()
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
            },
            projectObservation: { observation in
                projectVitalDBObservationBestEffort(observation)
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
