import Contracts
import Domain
import Network
import XCTest

final class UpdateBootstrapGuestControlProofPolicyTests: XCTestCase {
    func testAcceptsPersistedGuestURLWhoseHostAndPortMatchHostEndpoint() throws {
        XCTAssertNoThrow(
            try prove(
                "http://192.168.64.3:18330",
                guestAddress: "192.168.64.3"
            )
        )
    }

    func testAcceptsTrailingSlashOnTheRequiredPort() throws {
        XCTAssertNoThrow(
            try prove(
                "http://192.168.64.3:18330/",
                guestAddress: "192.168.64.3"
            )
        )
    }

    func testAcceptsIPv4TrailingDotHostAsTheSameAddress() throws {
        XCTAssertNoThrow(
            try prove(
                "http://192.168.64.3.:18330",
                guestAddress: "192.168.64.3"
            )
        )
    }

    func testComparesIPv4HostsByAddressEqualityNotStringEquality() throws {
        let padded = "192.168.064.003"
        if IPv4Address(padded) == IPv4Address("192.168.64.3") {
            XCTAssertNoThrow(
                try prove(
                    "http://192.168.64.3:18330",
                    guestAddress: padded
                )
            )
        } else {
            XCTAssertThrowsError(
                try prove(
                    "http://192.168.64.3:18330",
                    guestAddress: padded
                )
            ) { error in
                XCTAssertEqual(
                    error as? UpdateBootstrapGuestControlProofPolicyError,
                    .hostMismatch(
                        invocationHost: "192.168.64.3",
                        observedAddress: padded
                    )
                )
            }
        }
    }

    func testRejectsOmittedPortAsPortMismatchNotHostMatch() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3",
                guestAddress: "192.168.64.3"
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .portMismatch(
                    actual: nil,
                    expected: RuntimeGuestControlEndpointContract.port
                )
            )
        }
    }

    func testRejectsWrongPortAsPortMismatch() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18331",
                guestAddress: "192.168.64.3"
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .portMismatch(
                    actual: 18331,
                    expected: RuntimeGuestControlEndpointContract.port
                )
            )
        }
    }

    func testRejectsDefaultHTTPPortAsPortMismatch() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:80",
                guestAddress: "192.168.64.3"
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .portMismatch(
                    actual: 80,
                    expected: RuntimeGuestControlEndpointContract.port
                )
            )
        }
    }

    func testRejectsHostLoopbackEvenWhenCurrentObservationMatches() {
        XCTAssertThrowsError(
            try prove(
                "http://127.0.0.1:18330/",
                read: .loaded(address: "127.0.0.1", source: .platformAgent)
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .hostLoopback("http://127.0.0.1:18330/")
            )
        }
    }

    func testRejectsLocalhostLoopbackBeforeAddressCorrelation() {
        XCTAssertThrowsError(
            try prove(
                "http://LOCALHOST:18330/",
                read: .missing("vm ip missing")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .hostLoopback("http://LOCALHOST:18330/")
            )
        }
    }

    func testRejectsInvalidPersistedURLWithoutGuessingAHost() {
        XCTAssertThrowsError(
            try prove(
                "https://192.168.64.3:18330",
                guestAddress: "192.168.64.3"
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .invalidURL("https://192.168.64.3:18330")
            )
        }
    }

    func testPreservesMissingGuestAddressWithoutInferringFromTheURL() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18330",
                read: .missing("Guest address resource missing")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .guestAddressMissing("Guest address resource missing")
            )
        }
    }

    func testPreservesReadFailedGuestAddressWithoutComparingHosts() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18330",
                read: .readFailed("permission denied")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .guestAddressReadFailed("permission denied")
            )
        }
    }

    func testPreservesStaleGuestAddressAsStaleNotMismatch() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18330",
                read: .stale("lease expired")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .guestAddressStale("lease expired")
            )
        }
    }

    func testPreservesInvalidGuestAddressAsInvalid() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18330",
                read: .invalid("not an IPv4 address")
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .guestAddressInvalid("not an IPv4 address")
            )
        }
    }

    func testPreservesNotReportedGuestAddressWithoutDefaulting() {
        XCTAssertThrowsError(
            try prove("http://192.168.64.3:18330", read: .notReported)
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .guestAddressNotReported
            )
        }
    }

    func testRejectsHostMismatchBetweenInvocationAndCurrentObservation() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18330",
                guestAddress: "192.168.64.8"
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .hostMismatch(
                    invocationHost: "192.168.64.3",
                    observedAddress: "192.168.64.8"
                )
            )
        }
    }

    func testRejectsLoadedGuestAddressWithoutAnAddressValue() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18330",
                read: RuntimeGuestAddressReadResult(
                    state: .loaded,
                    address: nil,
                    source: .platformAgent
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .guestAddressReadFailed(
                    "loaded Guest address resource has no address"
                )
            )
        }
    }

    func testReportsHostMismatchBeforePortMismatch() {
        XCTAssertThrowsError(
            try prove(
                "http://192.168.64.3:18331",
                guestAddress: "192.168.64.8"
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapGuestControlProofPolicyError,
                .hostMismatch(
                    invocationHost: "192.168.64.3",
                    observedAddress: "192.168.64.8"
                )
            )
        }
    }

    private func prove(
        _ url: String,
        guestAddress: String
    ) throws {
        try prove(
            url,
            read: .loaded(address: guestAddress, source: .platformAgent)
        )
    }

    private func prove(
        _ url: String,
        read: RuntimeGuestAddressReadResult
    ) throws {
        try UpdateBootstrapGuestControlProofPolicy.prove(
            persistedGuestControlBaseURL: url,
            guestAddressRead: read,
            expectedPort: RuntimeGuestControlEndpointContract.port
        )
    }
}
