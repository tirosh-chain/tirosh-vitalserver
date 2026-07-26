import Application
import Contracts
import Domain
import XCTest

final class AuthorizeRuntimeUpdateApplyUseCaseTests: XCTestCase {
    func testAuthorizeReturnsExplicitDevelopmentDecisionForInstalledDevLauncher() throws {
        let decision = try AuthorizeRuntimeUpdateApplyUseCase().authorize(
            input: AuthorizeRuntimeUpdateApplyInput(
                installedChannel: .dev,
                trustIntent: .allowUnsignedDevelopmentBundle
            )
        )

        XCTAssertEqual(decision, .allowUnsignedDevelopmentBundle)
    }

    func testAuthorizePreservesStableLauncherRejection() {
        XCTAssertThrowsError(try AuthorizeRuntimeUpdateApplyUseCase().authorize(
            input: AuthorizeRuntimeUpdateApplyInput(
                installedChannel: .stable,
                trustIntent: .allowUnsignedDevelopmentBundle
            )
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateApplyTrustError,
                .unsignedDevelopmentIntentNotAllowed(installedChannel: .stable)
            )
        }
    }
}
