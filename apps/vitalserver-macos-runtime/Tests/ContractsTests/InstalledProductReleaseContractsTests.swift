import Contracts
import XCTest

final class InstalledProductReleaseContractsTests: XCTestCase {
    func testDecodesCompletePackageInstallRelease() throws {
        let release = try JSONDecoder().decode(
            InstalledProductRelease.self,
            from: Data(document.utf8)
        )

        XCTAssertEqual(release.productVersion, "0.2.2")
        XCTAssertEqual(release.releaseRevision, 1)
        XCTAssertEqual(release.source, .packageInstall)
    }

    func testRejectsUnknownField() {
        let invalid = document.dropLast() + #","legacyVersion":"0.2.1"}"#

        XCTAssertThrowsError(try JSONDecoder().decode(
            InstalledProductRelease.self,
            from: Data(invalid.utf8)
        ))
    }

    private var document: String {
        """
        {"schemaVersion":"v1","productId":"ai.tirosh.vitalserver.helper","productVersion":"0.2.2","runtimeVersion":"0.2.2","releaseRevision":1,"source":"package-install","installOperationId":"install-42","settledAt":"2026-07-27T01:00:00Z"}
        """
    }
}
