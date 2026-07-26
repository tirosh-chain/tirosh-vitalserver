import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class RuntimeHostTimeContractWriterTests: XCTestCase {
    func testWritesExplicitHostTimeFromInjectedClock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("host-time.json")
        let fixedTime = Date(timeIntervalSince1970: 1_784_100_123.75)
        let writer = RuntimeHostTimeContractWriter(
            destination: destination,
            fileStore: SystemRuntimeFileStore(),
            now: { fixedTime },
            log: { _ in }
        )

        try writer.write()

        let document = try JSONDecoder().decode(
            RuntimeHostTimeDocument.self,
            from: Data(contentsOf: destination)
        )
        XCTAssertEqual(document.epochSeconds, 1_784_100_123)
        XCTAssertEqual(
            document.updatedAt,
            ISO8601DateFormatter().string(from: fixedTime)
        )
    }
}
