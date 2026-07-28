@testable import UpdateRunnerHost
import XCTest

final class BundleOwnedProductUpdateRunnerTests: XCTestCase {
    func testRunnerRequiresOnlyFixedAbsoluteInvocationProtocol() {
        for arguments in [
            [],
            ["execute"],
            ["execute", "--invocation", "relative/invocation.json"],
            ["execute", "--other", "/updates/invocation.json"],
            [
                "execute",
                "--invocation",
                "/updates/invocation.json",
                "--extra",
            ],
        ] {
            XCTAssertThrowsError(
                try BundleOwnedProductUpdateRunner().run(
                    arguments: arguments
                )
            ) { error in
                XCTAssertEqual(
                    error as? BundleOwnedProductUpdateRunnerError,
                    .invalidArguments
                )
            }
        }
    }
}
