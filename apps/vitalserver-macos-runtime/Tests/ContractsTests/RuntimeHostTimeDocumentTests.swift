import Contracts
import XCTest

final class RuntimeHostTimeDocumentTests: XCTestCase {
    func testRuntimeHostTimeDocumentRoundTripsExplicitHostTime() throws {
        let document = RuntimeHostTimeDocument(
            epochSeconds: 1_781_273_647,
            updatedAt: "2026-06-13T10:14:07Z"
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(RuntimeHostTimeDocument.self, from: encoded)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.epochSeconds, 1_781_273_647)
        XCTAssertEqual(decoded.updatedAt, "2026-06-13T10:14:07Z")
    }
}
