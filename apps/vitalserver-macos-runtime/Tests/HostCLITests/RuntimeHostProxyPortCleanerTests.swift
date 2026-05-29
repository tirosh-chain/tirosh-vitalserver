import Foundation
import Core
@testable import HostCLI
import XCTest

final class RuntimeHostProxyPortCleanerTests: XCTestCase {
    func testStopsExpectedProxyNginxBeforeStartingProxy() throws {
        var lsofCalls = 0
        var commands: [(String, [String])] = []
        var sleeps: [TimeInterval] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceLoaded: { false },
            expectedProxyNginxPID: { "123" },
            ownedNginxPathFragments: ["/Library/Application Support/TiroshVitalServer/nginx"],
            runProcess: { executable, arguments in
                commands.append((executable, arguments))
                if executable == Constants.Commands.lsof {
                    lsofCalls += 1
                    return lsofCalls == 1
                        ? RuntimeProcessResult(exitCode: 0, stdout: Self.lsof(["nginx", "123"]), stderr: "")
                        : RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { sleeps.append($0) },
            log: { _ in }
        )

        try cleaner.cleanupBeforeStartingProxy()

        XCTAssertTrue(commands.contains { $0.0 == Constants.Commands.kill && $0.1 == ["-TERM", "123"] })
        XCTAssertEqual(sleeps, [1])
    }

    func testStopsOwnedProxyNginxByCommandLinePath() throws {
        var lsofCalls = 0
        var killed: [[String]] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceLoaded: { false },
            expectedProxyNginxPID: { nil },
            ownedNginxPathFragments: ["/Library/Application Support/TiroshVitalServer/nginx"],
            runProcess: { executable, arguments in
                switch executable {
                case Constants.Commands.lsof:
                    lsofCalls += 1
                    return lsofCalls == 1
                        ? RuntimeProcessResult(exitCode: 0, stdout: Self.lsof(["nginx", "456"]), stderr: "")
                        : RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
                case Constants.Commands.ps:
                    return RuntimeProcessResult(
                        exitCode: 0,
                        stdout: "/Library/Application Support/TiroshVitalServer/nginx/sbin/nginx -c vitalserver-nginx.conf\n",
                        stderr: ""
                    )
                case Constants.Commands.kill:
                    killed.append(arguments)
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                default:
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
            },
            sleep: { _ in },
            log: { _ in }
        )

        try cleaner.cleanupBeforeStartingProxy()

        XCTAssertEqual(killed, [["-TERM", "456"]])
    }

    func testLeavesExternalListenerAndThrowsClearError() {
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceLoaded: { false },
            expectedProxyNginxPID: { nil },
            ownedNginxPathFragments: ["/Library/Application Support/TiroshVitalServer/nginx"],
            runProcess: { executable, _ in
                if executable == Constants.Commands.lsof {
                    return RuntimeProcessResult(exitCode: 0, stdout: Self.lsof(["httpd", "789"]), stderr: "")
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { _ in XCTFail("external listener should not be terminated") },
            log: { _ in }
        )

        XCTAssertThrowsError(try cleaner.cleanupBeforeStartingProxy()) { error in
            XCTAssertTrue(String(describing: error).contains("external listener(s): httpd-789"))
        }
    }

    func testDoesNotStopConfiguredProxyWhenServiceIsLoaded() throws {
        var killed: [[String]] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceLoaded: { true },
            expectedProxyNginxPID: { "123" },
            ownedNginxPathFragments: ["/Library/Application Support/TiroshVitalServer/nginx"],
            runProcess: { executable, arguments in
                switch executable {
                case Constants.Commands.lsof:
                    return RuntimeProcessResult(exitCode: 0, stdout: Self.lsof(["nginx", "123"]), stderr: "")
                case Constants.Commands.kill:
                    killed.append(arguments)
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                default:
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
            },
            sleep: { _ in XCTFail("loaded configured proxy should not be terminated") },
            log: { _ in }
        )

        try cleaner.cleanupBeforeStartingProxy()

        XCTAssertTrue(killed.isEmpty)
    }

    private static func lsof(_ listener: [String]) -> String {
        """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        \(listener[0]) \(listener[1]) root 6u IPv4 0x1 0t0 TCP *:80 (LISTEN)
        """
    }
}
