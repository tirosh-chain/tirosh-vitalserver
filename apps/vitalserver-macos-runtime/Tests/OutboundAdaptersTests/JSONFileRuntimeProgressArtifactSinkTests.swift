import Contracts
import OutboundAdapters
import XCTest

final class JSONFileRuntimeProgressArtifactSinkTests: XCTestCase {
    func testSaveWritesProgressDocument() throws {
        let url = temporaryDirectory().appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeProgress)
        let sink = JSONFileRuntimeProgressArtifactSink(url: url)
        let progress = RuntimeProgressDocument(
            operation: .applyBundle,
            phase: .running,
            step: .activateGuestUpdate,
            stepStatus: .started,
            message: "step started",
            reasonCodes: ["activation"],
            startedAt: nil,
            updatedAt: "2026-07-08T00:00:00Z"
        )

        try sink.save(progress)

        let loaded = try JSONDecoder().decode(RuntimeProgressDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(loaded, progress)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
