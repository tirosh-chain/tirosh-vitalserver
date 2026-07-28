import Contracts
@testable import OutboundAdapters
import RuntimeControl
import XCTest

final class RuntimeTimeAuthorityReadersTests: XCTestCase {
    func testReadsExplicitTimeAuthorityDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let documentURL = directory.appendingPathComponent("time-authority.json")
        let document = RuntimeTimeAuthorityDocument(
            profile: .helperNTP,
            sourceId: "helper-host-clock",
            serverAddress: "192.168.64.1",
            serverPort: 123,
            state: .hostClockOnly,
            stratum: 10,
            allowedClientAddress: "192.168.64.3",
            updatedAt: "2026-07-28T07:25:32Z"
        )
        try JSONEncoder().encode(document).write(to: documentURL)

        let read = SystemRuntimeTimeAuthorityReader(
            documentURL: documentURL
        ).loadTimeAuthority()

        XCTAssertEqual(read.state, .loaded)
        XCTAssertEqual(read.document, document)
        XCTAssertNil(read.readError)
    }

    func testPreservesMissingAndDecodeFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let documentURL = directory.appendingPathComponent("time-authority.json")
        let reader = SystemRuntimeTimeAuthorityReader(documentURL: documentURL)

        XCTAssertEqual(reader.loadTimeAuthority().state, .missing)

        try Data("{\"schemaVersion\":".utf8).write(to: documentURL)
        let failed = reader.loadTimeAuthority()
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNotNil(failed.readError)
        XCTAssertNil(failed.document)
    }
}
