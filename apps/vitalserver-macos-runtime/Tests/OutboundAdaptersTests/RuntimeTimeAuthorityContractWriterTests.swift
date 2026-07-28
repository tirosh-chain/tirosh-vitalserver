import Contracts
@testable import OutboundAdapters
import XCTest

final class RuntimeTimeAuthorityContractWriterTests: XCTestCase {
    func testWritesRoundTrippableContractAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent(
            "time-authority.json"
        )
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

        try RuntimeTimeAuthorityContractWriter(
            destination: destination
        ).write(document)

        XCTAssertEqual(
            try JSONDecoder().decode(
                RuntimeTimeAuthorityDocument.self,
                from: Data(contentsOf: destination)
            ),
            document
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            ["time-authority.json"]
        )
    }
}
