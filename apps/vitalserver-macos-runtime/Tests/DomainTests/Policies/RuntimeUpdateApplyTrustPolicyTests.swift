import Contracts
import Domain
import XCTest

final class RuntimeUpdateApplyTrustPolicyTests: XCTestCase {
    func testDevChannelAllowsOnlyExplicitUnsignedDevelopmentIntent() throws {
        let decision = try RuntimeUpdateApplyTrustPolicy.authorize(
            installedChannel: .dev,
            intent: .allowUnsignedDevelopmentBundle
        )

        XCTAssertEqual(decision, .allowUnsignedDevelopmentBundle)
        XCTAssertEqual(
            decision.logMessage,
            "update apply trust override accepted installedChannel=dev publisherAuthenticity=unverified scope=local-development"
        )
    }

    func testDevChannelRejectsApplyWithoutExplicitUnsignedDevelopmentIntent() {
        XCTAssertThrowsError(try RuntimeUpdateApplyTrustPolicy.authorize(
            installedChannel: .dev,
            intent: .requireVerifiedPublisher
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateApplyTrustError,
                .publisherVerificationUnavailable(installedChannel: .dev)
            )
        }
    }

    func testStableChannelRejectsUnsignedDevelopmentIntent() {
        XCTAssertThrowsError(try RuntimeUpdateApplyTrustPolicy.authorize(
            installedChannel: .stable,
            intent: .allowUnsignedDevelopmentBundle
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateApplyTrustError,
                .unsignedDevelopmentIntentNotAllowed(installedChannel: .stable)
            )
        }
    }

    func testUnknownChannelRejectsUnsignedDevelopmentIntentWithoutDefaulting() {
        let channel = UpdateBundleChannel.unknown("preview")

        XCTAssertThrowsError(try RuntimeUpdateApplyTrustPolicy.authorize(
            installedChannel: channel,
            intent: .allowUnsignedDevelopmentBundle
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUpdateApplyTrustError,
                .unsignedDevelopmentIntentNotAllowed(installedChannel: channel)
            )
        }
    }

    func testTrustErrorsDescribeAuthenticityWithoutClaimingVerification() {
        XCTAssertEqual(
            RuntimeUpdateApplyTrustError.publisherVerificationUnavailable(
                installedChannel: .stable
            ).description,
            "update apply blocked installedChannel=stable reason=trusted-publisher-verification-unavailable"
        )
        XCTAssertEqual(
            RuntimeUpdateApplyTrustError.unsignedDevelopmentIntentNotAllowed(
                installedChannel: .stable
            ).description,
            "unsigned development bundle apply is not allowed for installedChannel=stable"
        )
    }
}
