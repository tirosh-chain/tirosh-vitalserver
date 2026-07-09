import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class RuntimeStatusWriterTests: XCTestCase {
    func testWriteStatusReturnsSnapshotWhileStatusDocumentOmitsVitalDBObservation() throws {
        let sink = RuntimeStatusWriterArtifactSinkSpy()
        let observation = vitalDBObservation()
        let snapshot = healthSnapshot(vitalDBObservation: observation)
        let statusDocumentUseCase = BuildRuntimeStatusDocumentUseCase()
        let reporter = RuntimeStatusReporter(
            statusArtifactSink: sink,
            progressArtifactSink: RuntimeStatusWriterProgressArtifactSinkSpy(),
            productIdentifier: "VitalServerHelper",
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            makeStatusDocument: statusDocumentUseCase.build,
            makeProgressDocument: statusDocumentUseCase.progressDocument
        )
        let writer = RuntimeStatusWriter(
            reporter: reporter,
            timestamp: { "2026-05-30T00:00:00Z" },
            runtimeVersion: { "0.1.0" },
            healthSnapshot: { snapshot },
            latestBackup: { nil }
        )

        let returnedSnapshot = try writer.writeStatus(.healthy)

        XCTAssertEqual(returnedSnapshot, snapshot)
        XCTAssertEqual(sink.saved?.status, .healthy)
    }

    func testWriteStatusPropagatesLatestBackupReadFailure() {
        let statusDocumentUseCase = BuildRuntimeStatusDocumentUseCase()
        let reporter = RuntimeStatusReporter(
            statusArtifactSink: RuntimeStatusWriterArtifactSinkSpy(),
            progressArtifactSink: RuntimeStatusWriterProgressArtifactSinkSpy(),
            productIdentifier: "VitalServerHelper",
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeHome: URL(fileURLWithPath: "/product/vm"),
            makeStatusDocument: statusDocumentUseCase.build,
            makeProgressDocument: statusDocumentUseCase.progressDocument
        )
        let writer = RuntimeStatusWriter(
            reporter: reporter,
            timestamp: { "2026-05-30T00:00:00Z" },
            runtimeVersion: { "0.1.0" },
            healthSnapshot: { healthSnapshot(vitalDBObservation: nil) },
            latestBackup: { throw RuntimeStatusWriterTestError.latestBackupReadFailed }
        )

        XCTAssertThrowsError(try writer.writeStatus(.healthy)) { error in
            XCTAssertEqual(error as? RuntimeStatusWriterTestError, .latestBackupReadFailed)
        }
    }
}

private enum RuntimeStatusWriterTestError: Error, Equatable {
    case latestBackupReadFailed
}

private final class RuntimeStatusWriterArtifactSinkSpy: RuntimeStatusArtifactSink {
    var saved: RuntimeStatusDocument?

    func save(_ document: RuntimeStatusDocument) throws {
        saved = document
    }
}

private final class RuntimeStatusWriterProgressArtifactSinkSpy: RuntimeProgressArtifactSink {
    func save(_ document: RuntimeProgressDocument) throws {}
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
