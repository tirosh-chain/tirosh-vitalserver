import Application
import Contracts
import XCTest

final class CleanRuntimeHostProxyPortUseCaseTests: XCTestCase {
    func testBeforeStartBlocksMissingProxyPortWithoutScanningOrStopping() {
        var scannedPorts: [Int] = []
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        let operations = makeOperations(
            proxyPort: { nil },
            portListenerScan: { port in
                scannedPorts.append(port)
                return .clear
            },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupBeforeStartingProxy(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("failed to read configured Host proxy port"))
            }
        XCTAssertTrue(scannedPorts.isEmpty)
        XCTAssertTrue(signals.isEmpty)
    }

    func testBeforeStartBlocksProxyServiceReadFailureBeforeStoppingOwnedListeners() {
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        let operations = makeOperations(
            proxyServiceState: { .readFailed("launchctl denied") },
            expectedProxyNginxPID: { .loaded("123") },
            portListenerScan: { _ in .loaded([
                RuntimeHostProxyListener(command: "nginx", pid: "123"),
            ]) },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupBeforeStartingProxy(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("failed to read Host proxy launchd service state"))
            }
        XCTAssertTrue(signals.isEmpty)
    }

    func testBeforeStartBlocksExternalListenerWithoutStoppingAnything() {
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        let external = RuntimeHostProxyListener(command: "httpd", pid: "456")
        let operations = makeOperations(
            portListenerScan: { _ in .loaded([external]) },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupBeforeStartingProxy(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("external listener(s): httpd-456"))
            }
        XCTAssertTrue(signals.isEmpty)
    }

    func testAfterStopReportsRemainingOwnedListenerAsExplicitFailure() {
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        var sleeps: [TimeInterval] = []
        let operations = makeOperations(
            expectedProxyNginxPID: { .loaded("123") },
            portListenerScan: { _ in .loaded([
                RuntimeHostProxyListener(command: "nginx", pid: "123"),
            ]) },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            },
            sleep: { sleeps.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupOwnedListenersAfterProxyStop(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("still held by VitalServer nginx listener(s): nginx-123"))
            }
        XCTAssertEqual(signals.map(\.0), ["123", "123"])
        XCTAssertEqual(signals.map(\.1), [.terminate, .kill])
        XCTAssertEqual(sleeps, [1, 1])
    }

    func testOwnershipPolicyClassifiesExpectedPIDAsOwnedWithoutCommandLineObservation() {
        let decision = RuntimeHostProxyNginxOwnershipPolicy.classify(
            listeners: [RuntimeHostProxyListener(command: "nginx", pid: "123")],
            expectedPID: "123",
            ownedNginxPathFragments: [],
            commandLineReadResults: [:]
        )

        XCTAssertEqual(
            decision,
            .classified(RuntimeHostProxyListenerClassification(ownedNginx: ["123"], external: []))
        )
    }

    func testOwnershipPolicyClassifiesOwnedCommandLineAndExternalListeners() {
        let owned = RuntimeHostProxyListener(command: "nginx", pid: "123")
        let externalNginx = RuntimeHostProxyListener(command: "nginx", pid: "456")
        let externalHttpd = RuntimeHostProxyListener(command: "httpd", pid: "789")

        let decision = RuntimeHostProxyNginxOwnershipPolicy.classify(
            listeners: [owned, externalNginx, externalHttpd],
            expectedPID: nil,
            ownedNginxPathFragments: ["/Library/Application Support/VitalServerHelper/nginx"],
            commandLineReadResults: [
                "123": .loaded("/Library/Application Support/VitalServerHelper/nginx/sbin/nginx -c vitalserver-nginx.conf"),
                "456": .loaded("/opt/homebrew/opt/nginx/bin/nginx -g daemon off;"),
            ]
        )

        XCTAssertEqual(
            decision,
            .classified(
                RuntimeHostProxyListenerClassification(
                    ownedNginx: ["123"],
                    external: [externalNginx, externalHttpd]
                )
            )
        )
    }

    func testBeforeStartBlocksCommandLineReadFailureBeforeStoppingOwnedListeners() {
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        let operations = makeOperations(
            portListenerScan: { _ in .loaded([
                RuntimeHostProxyListener(command: "nginx", pid: "456"),
            ]) },
            nginxCommandLine: { _ in .readFailed("exitCode=1 stderr=permission denied") },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupBeforeStartingProxy(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("failed to inspect Host proxy nginx command line"))
            }
        XCTAssertTrue(signals.isEmpty)
    }

    func testBeforeStartBlocksEmptyCommandLineBeforeStoppingOwnedListeners() {
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        let operations = makeOperations(
            portListenerScan: { _ in .loaded([
                RuntimeHostProxyListener(command: "nginx", pid: "456"),
            ]) },
            nginxCommandLine: { _ in .empty },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupBeforeStartingProxy(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("failed to inspect Host proxy nginx command line"))
            }
        XCTAssertTrue(signals.isEmpty)
    }

    func testBeforeStartBlocksPortListenerCommandFailureWithoutTreatingItAsClear() {
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        var logs: [String] = []
        let operations = makeOperations(
            portListenerScan: { _ in
                .commandFailed(
                    exitCode: 13,
                    reason: "exitCode=13 stderr=permission denied"
                )
            },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupBeforeStartingProxy(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("failed to inspect proxy port 80 listeners"))
                XCTAssertTrue(String(describing: error).contains("exitCode=13"))
            }
        XCTAssertTrue(signals.isEmpty)
        XCTAssertEqual(logs, [
            "proxy port listener scan failed port=80 exitCode=13 reason=exitCode=13 stderr=permission denied",
        ])
    }

    func testAfterStopBlocksMalformedPortListenerOutputWithoutTreatingItAsClear() {
        var signals: [(String, RuntimeHostProxyOwnedListenerSignal)] = []
        var logs: [String] = []
        let operations = makeOperations(
            portListenerScan: { _ in
                .malformedOutput(exitCode: 0, reason: "malformed lsof listener line=bad")
            },
            signalOwnedListener: { pid, signal in
                signals.append((pid, signal))
            },
            log: { logs.append($0) }
        )

        XCTAssertThrowsError(try CleanRuntimeHostProxyPortUseCase()
            .cleanupOwnedListenersAfterProxyStop(operations: operations)) { error in
                XCTAssertTrue(String(describing: error).contains("malformed lsof output"))
            }
        XCTAssertTrue(signals.isEmpty)
        XCTAssertEqual(logs, [
            "proxy port listener scan output malformed port=80 exitCode=0 reason=malformed lsof listener line=bad",
        ])
    }

    private func makeOperations(
        proxyPort: @escaping () -> Int? = { 80 },
        proxyServiceState: @escaping () -> RuntimeServiceState = { .notLoaded },
        expectedProxyNginxPID: @escaping () -> RuntimeProxyNginxPIDReadResult = { .missing },
        portListenerScan: @escaping (Int) -> RuntimeHostProxyListenerScanResult = { _ in .clear },
        ownedNginxPathFragments: [String] = ["/Library/Application Support/VitalServerHelper/nginx"],
        nginxCommandLine: @escaping (String) -> RuntimeHostProxyNginxCommandLineReadResult = { _ in .empty },
        signalOwnedListener: @escaping (String, RuntimeHostProxyOwnedListenerSignal) -> Void = { _, _ in },
        sleep: @escaping (TimeInterval) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> CleanRuntimeHostProxyPortOperations {
        CleanRuntimeHostProxyPortOperations(
            proxyPort: proxyPort,
            proxyServiceState: proxyServiceState,
            expectedProxyNginxPID: expectedProxyNginxPID,
            portListenerScan: portListenerScan,
            ownedNginxPathFragments: ownedNginxPathFragments,
            nginxCommandLine: nginxCommandLine,
            signalOwnedListener: signalOwnedListener,
            sleep: sleep,
            log: log
        )
    }
}
