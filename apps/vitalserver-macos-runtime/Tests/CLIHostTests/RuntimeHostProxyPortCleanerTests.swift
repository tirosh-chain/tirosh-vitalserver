import Foundation
import Bootstrap
import Application
import Contracts
import Domain
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeHostProxyPortCleanerTests: XCTestCase {
    func testPackageReinstallPreflightAllowsOnlyOwnedProxyListenersWithoutStoppingThem() throws {
        var killed: [[String]] = []
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .loaded },
            expectedProxyNginxPID: { .loaded("123") },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
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
            sleep: { _ in XCTFail("package reinstall preflight must not wait or stop listeners") },
            log: { logs.append($0) }
        )

        try CleanRuntimeHostProxyPortUseCase()
            .requirePackageReinstallPortAvailable(operations: cleaner.operations)

        XCTAssertTrue(killed.isEmpty)
        XCTAssertTrue(logs.contains { $0.contains("existing VitalServer nginx owns port=80 pids=123") })
    }

    func testPackageReinstallPreflightRejectsExternalListenerBeforeStoppingOwnedProxy() {
        var killed: [[String]] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .loaded },
            expectedProxyNginxPID: { .loaded("123") },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, arguments in
                switch executable {
                case Constants.Commands.lsof:
                    return RuntimeProcessResult(
                        exitCode: 0,
                        stdout: Self.lsof([
                            ["nginx", "123"],
                            ["OrbStack", "59042"],
                        ]),
                        stderr: ""
                    )
                case Constants.Commands.kill:
                    killed.append(arguments)
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                default:
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
            },
            sleep: { _ in XCTFail("package reinstall preflight must not wait or stop listeners") },
            log: { _ in }
        )

        XCTAssertThrowsError(
            try CleanRuntimeHostProxyPortUseCase()
                .requirePackageReinstallPortAvailable(operations: cleaner.operations)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("external listener(s): OrbStack-59042"))
        }
        XCTAssertTrue(killed.isEmpty)
    }

    func testStopsExpectedProxyNginxBeforeStartingProxy() throws {
        var lsofCalls = 0
        var commands: [(String, [String])] = []
        var sleeps: [TimeInterval] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .loaded("123") },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
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

        try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)

        XCTAssertTrue(commands.contains { $0.0 == Constants.Commands.kill && $0.1 == ["-TERM", "123"] })
        XCTAssertEqual(sleeps, [1])
    }

    func testStopsOwnedProxyNginxByCommandLinePath() throws {
        var lsofCalls = 0
        var killed: [[String]] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
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
                        stdout: "/Library/Application Support/VitalServerHelper/nginx/sbin/nginx -c vitalserver-nginx.conf\n",
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

        try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)

        XCTAssertEqual(killed, [["-TERM", "456"]])
    }

    func testLeavesExternalListenerAndThrowsClearError() {
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, _ in
                if executable == Constants.Commands.lsof {
                    return RuntimeProcessResult(exitCode: 0, stdout: Self.lsof(["httpd", "789"]), stderr: "")
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { _ in XCTFail("external listener should not be terminated") },
            log: { _ in }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("external listener(s): httpd-789"))
        }
    }

    func testCleanupAfterProxyStopStopsOwnedNginxAndLeavesExternalListener() throws {
        var lsofCalls = 0
        var killed: [[String]] = []
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, arguments in
                switch executable {
                case Constants.Commands.lsof:
                    lsofCalls += 1
                    if lsofCalls == 1 {
                        return RuntimeProcessResult(
                            exitCode: 0,
                            stdout: Self.lsof([
                                ["nginx", "456"],
                                ["httpd", "789"],
                            ]),
                            stderr: ""
                        )
                    }
                    return RuntimeProcessResult(
                        exitCode: 0,
                        stdout: Self.lsof([["httpd", "789"]]),
                        stderr: ""
                    )
                case Constants.Commands.ps:
                    if arguments.contains("456") {
                        return RuntimeProcessResult(
                            exitCode: 0,
                            stdout: "/Library/Application Support/VitalServerHelper/nginx/sbin/nginx -c vitalserver-nginx.conf\n",
                            stderr: ""
                        )
                    }
                    return RuntimeProcessResult(exitCode: 0, stdout: "/usr/sbin/httpd\n", stderr: "")
                case Constants.Commands.kill:
                    killed.append(arguments)
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                default:
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
            },
            sleep: { _ in },
            log: { logs.append($0) }
        )

        try CleanRuntimeHostProxyPortUseCase().cleanupOwnedListenersAfterProxyStop(operations: cleaner.operations)

        XCTAssertEqual(killed, [["-TERM", "456"]])
        XCTAssertTrue(logs.contains { $0.contains("leaving external listeners port=80 listeners=httpd-789") })
        XCTAssertTrue(logs.contains { $0.contains("proxy port cleanup after stop completed port=80") })
    }

    func testThrowsWhenPortListenerScanFails() {
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, _ in
                if executable == Constants.Commands.lsof {
                    return RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "permission denied")
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { _ in XCTFail("failed listener scan should not terminate anything") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to inspect proxy port 80 listeners"))
        }
        XCTAssertTrue(logs.contains { $0.contains("proxy port listener scan failed") })
    }

    func testTreatsEmptyLsofFailureAsNoListeners() throws {
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, _ in
                if executable == Constants.Commands.lsof {
                    return RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { _ in XCTFail("empty listener scan should not terminate anything") },
            log: { logs.append($0) }
        )

        try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)

        XCTAssertTrue(logs.contains { $0.contains("proxy port cleanup skipped; no listeners") })
    }

    func testOutputIssueLsofFailureBlocksCleanup() {
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, _ in
                if executable == Constants.Commands.lsof {
                    return RuntimeProcessResult(
                        exitCode: 1,
                        stdout: "",
                        stderr: "",
                        outputIssues: [
                            RuntimeCommandOutputIssue(stream: .stdout, message: "lsof stdout is not valid UTF-8"),
                        ]
                    )
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { _ in XCTFail("listener scan with output issue should not terminate anything") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to inspect proxy port 80 listeners"))
        }
        XCTAssertTrue(logs.contains { $0.contains("outputIssues=stdout:lsof stdout is not valid UTF-8") })
    }

    func testEmptyUnexpectedLsofFailureBlocksCleanup() {
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, _ in
                if executable == Constants.Commands.lsof {
                    return RuntimeProcessResult(exitCode: 2, stdout: "", stderr: "")
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { _ in XCTFail("unexpected listener scan failure should not terminate anything") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to inspect proxy port 80 listeners"))
        }
        XCTAssertTrue(logs.contains { $0.contains("proxy port listener scan failed port=80 exitCode=2") })
    }

    func testMalformedLsofSuccessBlocksCleanup() {
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, _ in
                if executable == Constants.Commands.lsof {
                    return RuntimeProcessResult(
                        exitCode: 0,
                        stdout: """
                        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                        malformed
                        """,
                        stderr: ""
                    )
                }
                return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
            },
            sleep: { _ in XCTFail("malformed listener scan should not terminate anything") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("malformed lsof output"))
        }
        XCTAssertTrue(logs.contains { $0.contains("proxy port listener scan output malformed") })
        XCTAssertTrue(logs.contains { $0.contains("malformed lsof listener line=malformed") })
    }

    func testCommandLineInspectionFailureBlocksNginxClassification() {
        var killed: [[String]] = []
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, arguments in
                switch executable {
                case Constants.Commands.lsof:
                    return RuntimeProcessResult(exitCode: 0, stdout: Self.lsof(["nginx", "456"]), stderr: "")
                case Constants.Commands.ps:
                    XCTAssertEqual(arguments, ["-p", "456", "-o", "command="])
                    return RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "permission denied")
                case Constants.Commands.kill:
                    killed.append(arguments)
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                default:
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
            },
            sleep: { _ in XCTFail("command line inspection failure should not terminate anything") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to inspect Host proxy nginx command line"))
        }
        XCTAssertTrue(killed.isEmpty)
        XCTAssertTrue(logs.contains { $0.contains("failed to inspect nginx command line pid=456") })
    }

    func testNginxListenerWithUnownedCommandLineIsExternalAndNotTerminated() {
        var killed: [[String]] = []
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .missing },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
            runProcess: { executable, arguments in
                switch executable {
                case Constants.Commands.lsof:
                    return RuntimeProcessResult(exitCode: 0, stdout: Self.lsof(["nginx", "456"]), stderr: "")
                case Constants.Commands.ps:
                    XCTAssertEqual(arguments, ["-p", "456", "-o", "command="])
                    return RuntimeProcessResult(exitCode: 0, stdout: "/opt/homebrew/opt/nginx/bin/nginx -g daemon off;\n", stderr: "")
                case Constants.Commands.kill:
                    killed.append(arguments)
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                default:
                    return RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
            },
            sleep: { _ in XCTFail("external nginx should not be terminated") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("external listener(s): nginx-456"))
        }
        XCTAssertTrue(killed.isEmpty)
        XCTAssertTrue(logs.contains { $0.contains("blocked by external listeners port=80 listeners=nginx-456") })
    }

    func testDoesNotStopConfiguredProxyWhenServiceIsLoaded() throws {
        var killed: [[String]] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .loaded },
            expectedProxyNginxPID: { .loaded("123") },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
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

        try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)

        XCTAssertTrue(killed.isEmpty)
    }

    func testProxyServiceStateReadFailureBlocksCleanupBeforeKillingListeners() {
        var killed: [[String]] = []
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .readFailed("launchctl failed") },
            expectedProxyNginxPID: { .loaded("123") },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
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
            sleep: { _ in XCTFail("service state read failure should not terminate anything") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to read Host proxy launchd service state"))
        }
        XCTAssertTrue(killed.isEmpty)
        XCTAssertTrue(logs.contains { $0.contains("failed to read proxy service state") })
    }

    func testExpectedProxyPIDReadFailureBlocksCleanupBeforeKillingListeners() {
        var killed: [[String]] = []
        var logs: [String] = []
        let cleaner = RuntimeHostProxyPortCleaner(
            proxyPort: { 80 },
            proxyServiceState: { .notLoaded },
            expectedProxyNginxPID: { .readFailed("permission denied") },
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            lsofPath: Constants.Commands.lsof,
            psPath: Constants.Commands.ps,
            killPath: Constants.Commands.kill,
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
            sleep: { _ in XCTFail("read failure should not terminate anything") },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase().cleanupBeforeStartingProxy(operations: cleaner.operations)) { error in
            XCTAssertTrue(String(describing: error).contains("failed to read expected Host proxy nginx PID"))
        }
        XCTAssertTrue(killed.isEmpty)
        XCTAssertTrue(logs.contains { $0.contains("failed to read expected nginx pid") })
    }

    private static func lsof(_ listener: [String]) -> String {
        lsof([listener])
    }

    private static func lsof(_ listeners: [[String]]) -> String {
        """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        \(listeners.map { "\($0[0]) \($0[1]) root 6u IPv4 0x1 0t0 TCP *:80 (LISTEN)" }.joined(separator: "\n"))
        """
    }
}
