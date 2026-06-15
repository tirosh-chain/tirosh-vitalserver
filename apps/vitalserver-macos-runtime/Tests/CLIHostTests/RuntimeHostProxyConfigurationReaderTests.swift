import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest
import Errors

final class RuntimeHostProxyConfigurationReaderTests: XCTestCase {
    func testInstalledProxyPortReaderLoadsConfiguredPort() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: "/Library/LaunchDaemons/proxy.plist")] = Data()
        let commandRunner = HostProxyConfigurationCommandRunner()
        commandRunner.result = RuntimeProcessResult(exitCode: 0, stdout: "8080\n", stderr: "")

        let state = makePortReader(fileStore: fileStore, commandRunner: commandRunner).read()

        XCTAssertEqual(state, .loaded(8080))
        XCTAssertEqual(commandRunner.requests, [
            HostProxyConfigurationCommandRequest(
                executable: "/usr/libexec/PlistBuddy",
                arguments: [
                    "-c",
                    "Print :EnvironmentVariables:VITALSERVER_PROXY_PORT",
                    "/Library/LaunchDaemons/proxy.plist",
                ]
            ),
        ])
    }

    func testInstalledProxyPortReaderUsesExplicitPlistPathStateForMissingConfig() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/Library/LaunchDaemons/proxy.plist"] = .missing
        let commandRunner = HostProxyConfigurationCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Entry, :EnvironmentVariables:VITALSERVER_PROXY_PORT, Does Not Exist"
        )

        let state = makePortReader(fileStore: fileStore, commandRunner: commandRunner).read()

        XCTAssertEqual(
            state,
            .missing("proxy launchd plist missing path=/Library/LaunchDaemons/proxy.plist")
        )
    }

    func testInstalledProxyPortReaderDoesNotInferMissingConfigFromCommandOutput() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: "/Library/LaunchDaemons/proxy.plist")] = Data()
        let commandRunner = HostProxyConfigurationCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Entry, :EnvironmentVariables:VITALSERVER_PROXY_PORT, Does Not Exist"
        )

        let state = makePortReader(fileStore: fileStore, commandRunner: commandRunner).read()

        XCTAssertEqual(
            state,
            .commandFailed(
                exitCode: 1,
                reason: "exitCode=1 stderr=Entry, :EnvironmentVariables:VITALSERVER_PROXY_PORT, Does Not Exist"
            )
        )
    }

    func testInstalledProxyPortReaderPreservesExecutionIssue() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: "/Library/LaunchDaemons/proxy.plist")] = Data()
        let commandRunner = HostProxyConfigurationCommandRunner()
        commandRunner.result = RuntimeProcessResult(
            exitCode: 127,
            stdout: "",
            stderr: "",
            executionIssue: RuntimeProcessExecutionIssue(
                kind: .processLaunchFailed,
                message: "PlistBuddy denied"
            )
        )

        let state = makePortReader(fileStore: fileStore, commandRunner: commandRunner).read()

        XCTAssertEqual(
            state,
            .commandFailed(
                exitCode: 127,
                reason: "exitCode=127 executionIssue=processLaunchFailed: PlistBuddy denied"
            )
        )
    }

    func testInstalledProxyPortReaderKeepsEmptyInvalidAndOutOfRangeDistinct() {
        let cases: [(RuntimeProcessResult, RuntimeProxyPortReadState)] = [
            (RuntimeProcessResult(exitCode: 0, stdout: "\n", stderr: ""), .empty),
            (RuntimeProcessResult(exitCode: 0, stdout: "abc\n", stderr: ""), .invalid("abc")),
            (RuntimeProcessResult(exitCode: 0, stdout: "70000\n", stderr: ""), .outOfRange(70000)),
        ]

        for (result, expected) in cases {
            let commandRunner = HostProxyConfigurationCommandRunner()
            commandRunner.result = result

            let state = makePortReader(commandRunner: commandRunner).read()

            XCTAssertEqual(state, expected)
        }
    }

    func testProxyNginxPIDReaderKeepsMissingEmptyLoadedAndReadFailureDistinct() {
        let url = URL(fileURLWithPath: "/product/run/proxy-nginx.pid")
        let fileStore = RuntimeFileStoreSpy()
        let reader = RuntimeProxyNginxPIDReader(url: url, fileStore: fileStore)

        XCTAssertEqual(reader.read(), .missing)

        fileStore.files[url] = Data("\n".utf8)
        XCTAssertEqual(reader.read(), .empty)

        fileStore.files[url] = Data("1234\n".utf8)
        XCTAssertEqual(reader.read(), .loaded("1234"))

        fileStore.readDataErrors[url] = CocoaError(.fileReadNoPermission)
        guard case .readFailed = reader.read() else {
            return XCTFail("expected proxy nginx PID read failure")
        }
    }

    func testProxyNginxPIDReaderReportsPathInspectionFailure() {
        let url = URL(fileURLWithPath: "/product/run/proxy-nginx.pid")
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates[url.path] = .inspectFailed("permission denied")

        let state = RuntimeProxyNginxPIDReader(url: url, fileStore: fileStore).read()

        XCTAssertEqual(
            state,
            .readFailed("proxy nginx PID path inspection failed path=/product/run/proxy-nginx.pid reason=permission denied")
        )
    }

    private func makePortReader(
        fileStore: RuntimeFileStoreSpy = RuntimeFileStoreSpy(),
        commandRunner: HostProxyConfigurationCommandRunner
    ) -> RuntimeInstalledProxyPortReader {
        RuntimeInstalledProxyPortReader(
            plistBuddyPath: "/usr/libexec/PlistBuddy",
            proxyLaunchDaemonPlist: "/Library/LaunchDaemons/proxy.plist",
            fileStore: fileStore,
            commandRunner: commandRunner
        )
    }
}

private struct HostProxyConfigurationCommandRequest: Equatable {
    let executable: String
    let arguments: [String]
}

private final class HostProxyConfigurationCommandRunner: RuntimeCommandRunner {
    var result = RuntimeProcessResult(exitCode: 0, stdout: "80\n", stderr: "")
    var requests: [HostProxyConfigurationCommandRequest] = []

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        requests.append(HostProxyConfigurationCommandRequest(executable: executable, arguments: arguments))
        return result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        run(executable, arguments: arguments)
    }
}
