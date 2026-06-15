import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest
import Errors

final class RuntimeHostProxyListenerScanReaderTests: XCTestCase {
    func testReadReportsUnavailableWhenLsofIsMissing() {
        let reader = makeReader(fileStore: RuntimeFileStoreSpy())

        XCTAssertEqual(reader.read(port: 8080), .unavailable)
    }

    func testReadReportsPresentButNotExecutableLsofAsInspectionFailure() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.fileStates["/usr/sbin/lsof"] = .present

        let reader = makeReader(fileStore: fileStore)

        XCTAssertEqual(
            reader.read(port: 8080),
            .inspectionFailed("path=/usr/sbin/lsof reason=not executable")
        )
    }

    func testReadReportsUnknownLsofFileStateAsInspectionFailure() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.fileStates["/usr/sbin/lsof"] = .unknown("symlink-loop")

        let reader = makeReader(fileStore: fileStore)

        XCTAssertEqual(
            reader.read(port: 8080),
            .inspectionFailed("path=/usr/sbin/lsof reason=unknown file state symlink-loop")
        )
    }

    func testReadReportsInspectionFailureSeparatelyFromUnavailable() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.fileStates["/usr/sbin/lsof"] = .inspectFailed("permission denied")

        let reader = makeReader(fileStore: fileStore)

        XCTAssertEqual(
            reader.read(port: 8080),
            .inspectionFailed("path=/usr/sbin/lsof reason=permission denied")
        )
    }

    func testReadTreatsOnlyEmptyExitOneAsClear() {
        let commandRunner = HostProxyListenerScanCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")

        let state = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(state, .clear)
    }

    func testReadLoadsListenersFromLsofOutput() {
        let commandRunner = HostProxyListenerScanCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            nginx 1234 root 10u IPv4 0x01 0t0 TCP *:8080 (LISTEN)
            httpd 456 root 11u IPv4 0x02 0t0 TCP *:8080 (LISTEN)
            """,
            stderr: ""
        )

        let state = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(
            state,
            .loaded([
                RuntimeHostProxyListener(command: "nginx", pid: "1234"),
                RuntimeHostProxyListener(command: "httpd", pid: "456"),
            ])
        )
        XCTAssertEqual(commandRunner.requests, [
            HostProxyListenerScanCommandRequest(
                executable: "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP:8080", "-sTCP:LISTEN"]
            ),
        ])
    }

    func testReadPreservesCommandFailureReason() {
        let commandRunner = HostProxyListenerScanCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 127,
            stdout: "",
            stderr: "",
            executionIssue: RuntimeProcessExecutionIssue(
                kind: .processLaunchFailed,
                message: "lsof denied"
            )
        )

        let state = makeReader(commandRunner: commandRunner).read(port: 8080)

        XCTAssertEqual(
            state,
            .commandFailed(
                exitCode: 127,
                reason: "exitCode=127 executionIssue=processLaunchFailed: lsof denied"
            )
        )
    }

    func testReadReportsMalformedOutputWithoutInventingListeners() {
        let commandRunner = HostProxyListenerScanCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 0,
            stdout: """
            COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            malformed
            """,
            stderr: ""
        )

        let state = makeReader(commandRunner: commandRunner).read(port: 8080)

        guard case .malformedOutput(let exitCode, let reason) = state else {
            return XCTFail("expected malformed output")
        }
        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(reason.contains("malformed lsof listener line=malformed"))
    }

    private func makeReader(
        fileStore: RuntimeFileStoreSpy = executableLsofFileStore(),
        commandRunner: HostProxyListenerScanCommandRunner = HostProxyListenerScanCommandRunner()
    ) -> RuntimeHostProxyListenerScanReader {
        RuntimeHostProxyListenerScanReader(
            lsofPath: "/usr/sbin/lsof",
            fileStore: fileStore,
            commandRunner: commandRunner
        )
    }
}

private func executableLsofFileStore() -> RuntimeFileStoreSpy {
    let fileStore = RuntimeFileStoreSpy()
    fileStore.files[URL(fileURLWithPath: "/usr/sbin/lsof")] = Data()
    return fileStore
}

private struct HostProxyListenerScanCommandRequest: Equatable {
    let executable: String
    let arguments: [String]
}

private final class HostProxyListenerScanCommandRunner: RuntimeCommandRunner {
    var result = RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
    var requests: [HostProxyListenerScanCommandRequest] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        requests.append(HostProxyListenerScanCommandRequest(executable: executable, arguments: arguments))
        return result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}
