import Application
import Contracts
import OutboundAdapters
import XCTest

final class RuntimeHostProxyPortCleanerTests: XCTestCase {
    func testOperationsPreserveEmptyExitOneLsofAsExplicitClearScan() {
        let cleaner = makeCleaner(
            result: RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
        )

        XCTAssertEqual(cleaner.operations.portListenerScan(80), .clear)
    }

    func testOperationsPreserveLsofCommandFailureAsTypedScanFailure() {
        let cleaner = makeCleaner(
            result: RuntimeProcessResult(
                exitCode: 13,
                stdout: "",
                stderr: "permission denied"
            )
        )

        XCTAssertEqual(
            cleaner.operations.portListenerScan(80),
            .commandFailed(
                exitCode: 13,
                reason: "exitCode=13 stderr=permission denied"
            )
        )
    }

    func testOperationsPreserveMalformedLsofOutputWithoutInventingClearState() {
        let cleaner = makeCleaner(
            result: RuntimeProcessResult(
                exitCode: 0,
                stdout: """
                COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                malformed
                """,
                stderr: ""
            )
        )

        guard case .malformedOutput(let exitCode, let reason) = cleaner.operations.portListenerScan(80) else {
            return XCTFail("expected malformedOutput")
        }
        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(reason.contains("malformed lsof listener line=malformed"))
    }

    func testOperationsLoadLsofListenersAsTypedScanResult() {
        let cleaner = makeCleaner(
            result: RuntimeProcessResult(
                exitCode: 0,
                stdout: """
                COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                nginx 123 root 10u IPv4 0x01 0t0 TCP *:80 (LISTEN)
                """,
                stderr: ""
            )
        )

        XCTAssertEqual(
            cleaner.operations.portListenerScan(80),
            .loaded([
                RuntimeHostProxyListener(command: "nginx", pid: "123"),
            ])
        )
    }

    private func makeCleaner(result: RuntimeProcessResult) -> RuntimeHostProxyPortCleaner {
        RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: "/usr/sbin/lsof",
            psPath: "/bin/ps",
            killPath: "/bin/kill",
            runProcess: { _, _ in result },
            sleep: { _ in },
            log: { _ in }
        )
    }
}
