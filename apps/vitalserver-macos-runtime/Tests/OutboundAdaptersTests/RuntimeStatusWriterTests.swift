import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class RuntimeStatusWriterTests: XCTestCase {
    func testWriteStatusWritesDocumentAndReturnsSnapshotForExplicitProjection() throws {
        let repository = RuntimeStatusWriterRepositorySpy()
        let observation = vitalDBObservation()
        let snapshot = healthSnapshot(vitalDBObservation: observation)
        let statusDocumentUseCase = BuildRuntimeStatusDocumentUseCase()
        let reporter = RuntimeStatusReporter(
            repository: repository,
            productIdentifier: "VitalServerHelper",
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            makeStatusDocument: statusDocumentUseCase.build,
            makeProgressDocument: statusDocumentUseCase.progressUpdate
        )
        let writer = RuntimeStatusWriter(
            reporter: reporter,
            timestamp: { "2026-05-30T00:00:00Z" },
            runtimeVersion: { "0.1.0" },
            healthSnapshot: { snapshot },
            latestBackup: { nil }
        )

        let returnedSnapshot = try writer.writeStatus(
            .healthy,
            operation: .health,
            message: "runtime health check passed"
        )

        XCTAssertEqual(returnedSnapshot, snapshot)
        XCTAssertEqual(repository.saved?.status, .healthy)
        XCTAssertEqual(repository.saved?.vitalDBObservation, observation)
    }

    func testWriteStatusPropagatesLatestBackupReadFailure() {
        let statusDocumentUseCase = BuildRuntimeStatusDocumentUseCase()
        let reporter = RuntimeStatusReporter(
            repository: RuntimeStatusWriterRepositorySpy(),
            productIdentifier: "VitalServerHelper",
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            makeStatusDocument: statusDocumentUseCase.build,
            makeProgressDocument: statusDocumentUseCase.progressUpdate
        )
        let writer = RuntimeStatusWriter(
            reporter: reporter,
            timestamp: { "2026-05-30T00:00:00Z" },
            runtimeVersion: { "0.1.0" },
            healthSnapshot: { healthSnapshot(vitalDBObservation: nil) },
            latestBackup: { throw RuntimeStatusWriterTestError.latestBackupReadFailed }
        )

        XCTAssertThrowsError(try writer.writeStatus(
            .healthy,
            operation: .health,
            message: "runtime health check passed"
        )) { error in
            XCTAssertEqual(error as? RuntimeStatusWriterTestError, .latestBackupReadFailed)
        }
    }
}

private enum RuntimeStatusWriterTestError: Error, Equatable {
    case latestBackupReadFailed
}

private final class RuntimeStatusWriterRepositorySpy: RuntimeStatusRepository {
    var result: RuntimeStatusDocumentLoadResult = .missing
    var saved: RuntimeStatusDocument?

    func loadResult() -> RuntimeStatusDocumentLoadResult {
        result
    }

    func save(_ document: RuntimeStatusDocument) throws {
        saved = document
    }
}

private func healthSnapshot(vitalDBObservation: VitalDBObservationDocument?) -> RuntimeHealthSnapshot {
    RuntimeHealthSnapshot(
        vmExecutable: .executable,
        proxyExecutable: .executable,
        rootfsBase: .present,
        vmDisk: .present,
        vmService: .loaded,
        proxyService: .loaded,
        watchdogService: .loaded,
        vmState: .running,
        vmErrors: [],
        vmIP: "192.168.64.2",
        proxyPort: 80,
        hostProxyHTTP: "200",
        guestHTTP: "200",
        redisUIHTTP: "200",
        swaggerUIHTTP: "200",
        vitalDBObservation: vitalDBObservation,
        failureReasons: []
    )
}

private func vitalDBObservation() -> VitalDBObservationDocument {
    VitalDBObservationDocument(
        observedAt: "2026-05-30T00:00:00Z",
        ready: true,
        recorderOnlineThresholdSeconds: 30,
        recorders: [
            VitalDBRecorderObservation(vrcode: "VR_TEST", ip: "10.200.10.10", online: true),
        ]
    )
}
