import Domain
import XCTest

final class UpdateBootstrapIdentifierSyntaxTests: XCTestCase {
    func testAcceptsStableASCIIIdentifiersAndVersions() {
        XCTAssertTrue(UpdateBootstrapIdentifierSyntax.isIdentifier("helper-release-key-2026"))
        XCTAssertTrue(UpdateBootstrapIdentifierSyntax.isIdentifier("._-start"))
        XCTAssertTrue(UpdateBootstrapIdentifierSyntax.isVersion("0.2.2+macos.1"))
        XCTAssertFalse(UpdateBootstrapIdentifierSyntax.isIdentifier(""))
        XCTAssertFalse(UpdateBootstrapIdentifierSyntax.isIdentifier(String(repeating: "a", count: 129)))
        XCTAssertFalse(UpdateBootstrapIdentifierSyntax.isIdentifier("helper:key"))
        XCTAssertFalse(UpdateBootstrapIdentifierSyntax.isIdentifier("helper-update-한글"))
        XCTAssertFalse(UpdateBootstrapIdentifierSyntax.isVersion("0.2.2:rc1"))
    }
}
