import Contracts
@testable import Domain
import XCTest
import Errors

final class RuntimeHostProxyListenerPolicyTests: XCTestCase {
    func testClearScanHasNoFailureReasons() {
        XCTAssertEqual(
            RuntimeHostProxyListenerPolicy.failureReasons(
                port: 8080,
                scanResult: .clear,
                expectedNginxPID: .missing
            ),
            []
        )
    }

    func testUnavailableAndInspectionFailedRemainDistinct() {
        XCTAssertEqual(
            RuntimeHostProxyListenerPolicy.failureReasons(
                port: 8080,
                scanResult: .unavailable,
                expectedNginxPID: .missing
            ),
            [.hostProxyListenerScanUnavailable]
        )
        XCTAssertEqual(
            RuntimeHostProxyListenerPolicy.failureReasons(
                port: 8080,
                scanResult: .inspectionFailed("path=/usr/sbin/lsof reason=permission denied"),
                expectedNginxPID: .missing
            ),
            [.hostProxyListenerScanInspectionFailed("path=/usr/sbin/lsof reason=permission denied")]
        )
    }

    func testExpectedNginxListenerDoesNotReportProxyPortFailure() {
        let listeners = [
            RuntimeHostProxyListener(command: "nginx", pid: "1234"),
        ]

        XCTAssertEqual(
            RuntimeHostProxyListenerPolicy.failureReasons(
                port: 8080,
                scanResult: .loaded(listeners),
                expectedNginxPID: .loaded("1234")
            ),
            []
        )
    }

    func testMissingExpectedPIDReportsListenerMismatch() {
        let listeners = [
            RuntimeHostProxyListener(command: "nginx", pid: "1234"),
        ]

        XCTAssertEqual(
            RuntimeHostProxyListenerPolicy.failureReasons(
                port: 8080,
                scanResult: .loaded(listeners),
                expectedNginxPID: .missing
            ),
            [.hostProxyListenerMismatch(port: 8080, listeners: "nginx-1234")]
        )
    }

    func testDifferentExpectedPIDReportsPortInUse() {
        let listeners = [
            RuntimeHostProxyListener(command: "nginx", pid: "1234"),
        ]

        XCTAssertEqual(
            RuntimeHostProxyListenerPolicy.failureReasons(
                port: 8080,
                scanResult: .loaded(listeners),
                expectedNginxPID: .loaded("9999")
            ),
            [.proxyPortInUse(port: 8080, listeners: "nginx-1234")]
        )
    }

    func testUnreadableExpectedPIDReportsConfigInvalidAndMismatch() {
        let listeners = [
            RuntimeHostProxyListener(command: "nginx", pid: "1234"),
        ]

        XCTAssertEqual(
            RuntimeHostProxyListenerPolicy.failureReasons(
                port: 8080,
                scanResult: .loaded(listeners),
                expectedNginxPID: .readFailed("permission denied")
            ),
            [
                .hostProxyConfigInvalid,
                .hostProxyListenerMismatch(port: 8080, listeners: "nginx-1234"),
            ]
        )
    }
}
