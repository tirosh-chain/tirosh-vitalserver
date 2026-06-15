import Contracts
@testable import Domain
import XCTest

final class RuntimeGuestRuntimeStatePolicyTests: XCTestCase {
    func testFreshStateBuildsExplicitInputFromReportedGuestState() {
        let assessment = RuntimeGuestRuntimeStatePolicy.inputAssessment(
            freshState: guestState(vmIP: "192.168.64.2", guestHTTP: "200"),
            loadedState: guestState(vmIP: "192.168.64.2", guestHTTP: "200"),
            readFailureReasons: []
        )

        XCTAssertEqual(assessment.state, .fresh(vmIP: "192.168.64.2", guestHTTP: .reportedStatus("200")))
        XCTAssertEqual(assessment.failureReasons, [])
    }

    func testFreshStatePreservesMissingVMIPAndBootstrapHTTPAsReportedState() {
        let assessment = RuntimeGuestRuntimeStatePolicy.inputAssessment(
            freshState: guestState(vmIP: "", guestHTTP: RuntimeHTTPStatusText.bootstrapPending),
            loadedState: nil,
            readFailureReasons: []
        )

        XCTAssertEqual(
            assessment.state,
            .fresh(vmIP: nil, guestHTTP: .reportedStatus(RuntimeHTTPStatusText.bootstrapPending))
        )
        XCTAssertEqual(assessment.failureReasons, [])
    }

    func testFreshStateReportsMissingGuestHTTPAsInvalidProviderContract() {
        let assessment = RuntimeGuestRuntimeStatePolicy.inputAssessment(
            freshState: guestState(vmIP: "192.168.64.2", guestHTTP: nil),
            loadedState: nil,
            readFailureReasons: []
        )

        XCTAssertEqual(assessment.state, .fresh(vmIP: "192.168.64.2", guestHTTP: .missing))
        XCTAssertEqual(assessment.failureReasons, [.guestRuntimeStateInvalid])
    }

    func testNonNumericGuestHTTPFailureIsProbeFailureNotMissingState() {
        let assessment = RuntimeGuestRuntimeStatePolicy.inputAssessment(
            freshState: guestState(vmIP: "192.168.64.2", guestHTTP: "curl-timeout"),
            loadedState: nil,
            readFailureReasons: []
        )

        XCTAssertEqual(assessment.state, .fresh(vmIP: "192.168.64.2", guestHTTP: .probeFailed("curl-timeout")))
        XCTAssertEqual(assessment.failureReasons, [])
    }

    func testMissingInvalidAndStaleRemainDistinct() {
        XCTAssertEqual(
            RuntimeGuestRuntimeStatePolicy.inputAssessment(
                freshState: nil,
                loadedState: nil,
                readFailureReasons: []
            ).state,
            .missing
        )
        XCTAssertEqual(
            RuntimeGuestRuntimeStatePolicy.inputAssessment(
                freshState: nil,
                loadedState: nil,
                readFailureReasons: [.guestRuntimeStateInvalid]
            ).state,
            .invalid
        )
        XCTAssertEqual(
            RuntimeGuestRuntimeStatePolicy.inputAssessment(
                freshState: nil,
                loadedState: guestState(vmIP: "192.168.64.2", guestHTTP: "200"),
                readFailureReasons: []
            ).state,
            .stale
        )
    }

    func testGuestDiskHealthErrorsAreDerivedFromExplicitGuestContract() {
        let errors = RuntimeGuestRuntimeStatePolicy.reportedVMErrors(
            from: GuestDiskHealthDocument(
                rootFilesystemReadOnly: true,
                kernelErrors: [
                    "EXT4-fs error: metadata checksum invalid",
                    "Buffer I/O error on dev vda",
                    "Remounting filesystem read-only",
                    "Buffer I/O error on dev vda",
                ]
            )
        )

        XCTAssertEqual(errors, [
            .guestFilesystemReadOnly,
            .guestFilesystemError,
            .guestDiskIO,
        ])
    }

    private func guestState(
        vmIP: String?,
        guestHTTP: String?
    ) -> GuestRuntimeStateDocument {
        GuestRuntimeStateDocument(
            vmIP: vmIP,
            guestHTTP: guestHTTP,
            redisUIHTTP: nil,
            swaggerUIHTTP: nil
        )
    }
}
