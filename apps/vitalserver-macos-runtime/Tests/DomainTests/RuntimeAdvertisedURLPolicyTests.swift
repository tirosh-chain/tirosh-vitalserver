import Domain
import XCTest

final class RuntimeAdvertisedURLPolicyTests: XCTestCase {
    func testAcceptsAbsoluteHTTPAndHTTPSAdvertisedURLs() {
        XCTAssertTrue(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL("https://vitaldb.tirosh.ai/"))
        XCTAssertTrue(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL("http://vitaldb.tirosh.ai:8080/path"))
    }

    func testRejectsMissingInvalidOrAmbiguousAdvertisedURLs() {
        XCTAssertFalse(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL(""))
        XCTAssertFalse(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL(" vitaldb.tirosh.ai"))
        XCTAssertFalse(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL("vitaldb.tirosh.ai"))
        XCTAssertFalse(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL("ftp://vitaldb.tirosh.ai/"))
        XCTAssertFalse(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL("https://vitaldb.tirosh.ai/\n"))
        XCTAssertFalse(RuntimeAdvertisedURLPolicy.isValidAdvertisedURL("https://vitaldb.tirosh.ai:70000/"))
    }

    func testCompatibilityEndpointPreservesExplicitPortAndSchemeDefaults() {
        XCTAssertEqual(
            RuntimeAdvertisedURLPolicy.compatibilityEndpoint(
                forAdvertisedURL: "https://vitaldb.tirosh.ai/",
                defaultPublicPort: 80
            ),
            RuntimeAdvertisedEndpoint(publicHost: "vitaldb.tirosh.ai", publicPort: 443)
        )
        XCTAssertEqual(
            RuntimeAdvertisedURLPolicy.compatibilityEndpoint(
                forAdvertisedURL: "http://vitaldb.tirosh.ai/",
                defaultPublicPort: 80
            ),
            RuntimeAdvertisedEndpoint(publicHost: "vitaldb.tirosh.ai", publicPort: 80)
        )
        XCTAssertEqual(
            RuntimeAdvertisedURLPolicy.compatibilityEndpoint(
                forAdvertisedURL: "https://vitaldb.tirosh.ai:8443/",
                defaultPublicPort: 80
            ),
            RuntimeAdvertisedEndpoint(publicHost: "vitaldb.tirosh.ai", publicPort: 8443)
        )
    }

    func testCompatibilityEndpointDoesNotInferEndpointFromInvalidURL() {
        XCTAssertNil(RuntimeAdvertisedURLPolicy.compatibilityEndpoint(
            forAdvertisedURL: "vitaldb.tirosh.ai",
            defaultPublicPort: 80
        ))
    }
}
