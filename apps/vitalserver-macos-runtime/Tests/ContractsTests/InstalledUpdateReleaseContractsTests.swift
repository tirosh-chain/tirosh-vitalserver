import Contracts
import XCTest

final class InstalledUpdateReleaseContractsTests: XCTestCase {
    func testDecodesCompleteInstalledRelease() throws {
        let release = try JSONDecoder().decode(
            InstalledUpdateRelease.self,
            from: Data(document.utf8)
        )

        XCTAssertEqual(release.productVersion, "0.2.2")
        XCTAssertEqual(release.journalRevision, 4)
    }

    func testRejectsUnknownField() {
        let invalid = document.dropLast() + #","legacyVersion":"0.2.1"}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                InstalledUpdateRelease.self,
                from: Data(invalid.utf8)
            ))
    }

    private var document: String {
        """
        {"schemaVersion":"v1","productId":"ai.tirosh.vitalserver.helper","productVersion":"0.2.2","runtimeVersion":"0.2.2","updateId":"update-42","journalId":"update-42","journalRevision":4,"reportRelativePath":"handoff/report.json","reportSHA256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","settledAt":"2026-07-27T01:00:00Z"}
        """
    }
}
