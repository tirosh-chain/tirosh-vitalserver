import Contracts
import Application
import Bootstrap
import Domain
import OutboundAdapters
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeFreshInstallPreflightRunnerTests: XCTestCase {
    func testSettingsReaderReportsMissingSettingsWithoutDefaulting() {
        let fileStore = RuntimeFileStoreSpy()

        let state = RuntimeInstallSettingsStateReader.state(
            path: "/private/tmp/tirosh-vitalserver-install.json",
            fileStore: fileStore
        )

        XCTAssertEqual(
            state,
            .missing(path: "/private/tmp/tirosh-vitalserver-install.json")
        )
    }

    func testSettingsReaderReportsInspectionFailureWithoutDefaulting() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.pathStates[url.path] = .inspectFailed("permission denied")

        let state = RuntimeInstallSettingsStateReader.state(
            path: url.path,
            fileStore: fileStore
        )

        XCTAssertEqual(
            state,
            .readFailed(path: url.path, reason: "settings path inspection failed: permission denied")
        )
    }

    func testSettingsReaderReportsDirectoryPathWithoutDefaulting() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.pathStates[url.path] = .directory

        let state = RuntimeInstallSettingsStateReader.state(
            path: url.path,
            fileStore: fileStore
        )

        XCTAssertEqual(
            state,
            .readFailed(path: url.path, reason: "settings path state is unexpected: directory")
        )
    }

    func testSettingsReaderReportsLoadedProxyPort() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.files[url] = Data(#"{"proxyPort":8080}"#.utf8)

        let state = RuntimeInstallSettingsStateReader.state(
            path: url.path,
            fileStore: fileStore
        )

        XCTAssertEqual(state, .loaded(path: url.path, proxyPort: 8080))
    }

    func testSettingsReaderReportsMissingProxyPortWithoutDefaulting() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.files[url] = Data(#"{}"#.utf8)

        let state = RuntimeInstallSettingsStateReader.state(
            path: url.path,
            fileStore: fileStore
        )

        XCTAssertEqual(state, .proxyPortMissing(path: url.path))
    }

    func testSettingsReaderReportsInvalidProxyPortWithoutDefaulting() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.files[url] = Data(#"{"proxyPort":70000}"#.utf8)

        let state = RuntimeInstallSettingsStateReader.state(
            path: url.path,
            fileStore: fileStore
        )

        XCTAssertEqual(
            state,
            .invalid(path: url.path, reason: "proxyPort out of range value=70000")
        )
    }

    func testSettingsReaderReportsDecodeFailureAsInvalid() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.files[url] = Data(#"{"proxyPort":"80"}"#.utf8)

        let state = RuntimeInstallSettingsStateReader.state(
            path: url.path,
            fileStore: fileStore
        )

        guard case .invalid(let path, let reason) = state else {
            return XCTFail("expected invalid settings state, got \(state)")
        }
        XCTAssertEqual(path, url.path)
        XCTAssertFalse(reason.isEmpty)
    }

    func testArtifactReaderUsesRuntimeFileStorePathStateWithoutDirectFileManagerRead() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/present-file"] = .file
        fileStore.pathStates["/present-directory"] = .directory
        fileStore.pathStates["/denied"] = .inspectFailed("permission denied")
        fileStore.pathStates["/unknown"] = .unknown("socket")

        XCTAssertEqual(
            RuntimeInstallArtifactStateReader.state(path: "/missing", fileStore: fileStore),
            .absent(path: "/missing")
        )
        XCTAssertEqual(
            RuntimeInstallArtifactStateReader.state(path: "/present-file", fileStore: fileStore),
            .present(path: "/present-file")
        )
        XCTAssertEqual(
            RuntimeInstallArtifactStateReader.state(path: "/present-directory", fileStore: fileStore),
            .present(path: "/present-directory")
        )
        XCTAssertEqual(
            RuntimeInstallArtifactStateReader.state(path: "/denied", fileStore: fileStore),
            .inspectFailed(path: "/denied", reason: "permission denied")
        )
        XCTAssertEqual(
            RuntimeInstallArtifactStateReader.state(path: "/unknown", fileStore: fileStore),
            .inspectFailed(path: "/unknown", reason: "unexpected path state: socket")
        )
    }

    func testFreshInstallPreflightCompositionReadsArtifactStatesFromProvidedFileStore() {
        let installedPaths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates[installedPaths.productRoot.path] = .inspectFailed("permission denied")

        let operations = RuntimeFreshInstallPreflightComposition.make(
            context: RuntimeFreshInstallPreflightCompositionContext(installedPaths: installedPaths),
            operations: RuntimeFreshInstallPreflightCompositionOperations(
                fileStore: fileStore,
                serviceState: { _ in .notLoaded },
                packageReceiptStates: { [] },
                proxyPortState: { .clear(port: $0) }
            )
        )

        XCTAssertTrue(operations.artifactStates().contains(
            .inspectFailed(path: installedPaths.productRoot.path, reason: "permission denied")
        ))
    }

    func testFreshInstallArtifactContractDoesNotTreatRetainedUninstallDataAsInstalledPayload() {
        let installedPaths = InstalledRuntimePaths(
            productRoot: URL(fileURLWithPath: "/Library/Application Support/VitalServerHelper")
        )

        let artifactPaths = RuntimeFreshInstallPreflightComposition
            .freshInstallArtifactPaths(installedPaths: installedPaths)

        XCTAssertTrue(artifactPaths.contains(installedPaths.productRoot))
        XCTAssertTrue(artifactPaths.contains(installedPaths.uninstaller))
        XCTAssertFalse(artifactPaths.contains(installedPaths.standardUninstallRetainedDataRoot))
    }

    func testProxyPortReaderDistinguishesClearOccupiedAndInspectFailed() {
        let clear = proxyPortState(result:
            RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
        )
        let occupied = proxyPortState(result:
            RuntimeProcessResult(
                exitCode: 0,
                stdout: """
                COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                nginx 123 root 6u IPv4 0 0t0 TCP *:80 (LISTEN)
                httpd 456 root 6u IPv4 0 0t0 TCP *:80 (LISTEN)
                """,
                stderr: ""
            )
        )
        let failed = proxyPortState(result:
            RuntimeProcessResult(exitCode: 2, stdout: "", stderr: "permission denied")
        )
        let outputIssueFailed = proxyPortState(result:
            RuntimeProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "",
                outputIssues: [
                    RuntimeCommandOutputIssue(stream: .stdout, message: "lsof stdout is not valid UTF-8"),
                ]
            )
        )
        let launchFailed = proxyPortState(result:
            RuntimeProcessResult(
                exitCode: 127,
                stdout: "",
                stderr: "",
                executionIssue: RuntimeProcessExecutionIssue(
                    kind: .processLaunchFailed,
                    message: "lsof denied"
                )
            )
        )
        let malformedOutputFailed = proxyPortState(result:
            RuntimeProcessResult(
                exitCode: 0,
                stdout: """
                COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                malformed
                """,
                stderr: ""
            )
        )

        XCTAssertEqual(clear, .clear(port: 80))
        XCTAssertEqual(occupied, .occupied(port: 80, listeners: "httpd/456,nginx/123"))
        XCTAssertEqual(failed, .inspectFailed(port: 80, reason: "exitCode=2 stderr=permission denied"))
        XCTAssertEqual(
            outputIssueFailed,
            .inspectFailed(port: 80, reason: "exitCode=1 outputIssues=stdout:lsof stdout is not valid UTF-8")
        )
        XCTAssertEqual(
            launchFailed,
            .inspectFailed(port: 80, reason: "exitCode=127 executionIssue=processLaunchFailed: lsof denied")
        )
        XCTAssertEqual(
            malformedOutputFailed,
            .inspectFailed(port: 80, reason: "malformed lsof listener line=malformed")
        )
    }

    func testProxyPortReaderPreservesLsofFileStateFailures() {
        let missingFileStore = RuntimeFileStoreSpy()
        let deniedFileStore = RuntimeFileStoreSpy()
        deniedFileStore.fileStates[Constants.Commands.lsof] = .inspectFailed("permission denied")

        XCTAssertEqual(
            proxyPortState(fileStore: missingFileStore, result: RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")),
            .inspectFailed(port: 80, reason: "lsof unavailable")
        )
        XCTAssertEqual(
            proxyPortState(fileStore: deniedFileStore, result: RuntimeProcessResult(exitCode: 0, stdout: "", stderr: "")),
            .inspectFailed(port: 80, reason: "path=\(Constants.Commands.lsof) reason=permission denied")
        )
    }

}

private func proxyPortState(
    port: Int = 80,
    fileStore: RuntimeFileStoreSpy = executableLsofFileStore(),
    result: RuntimeProcessResult
) -> RuntimeHostProxyPortState {
    RuntimeHostProxyPortStateReader.state(
        port: port,
        lsofPath: Constants.Commands.lsof,
        fileStore: fileStore,
        commandRunner: FreshInstallPreflightCommandRunner(result: result)
    )
}

private func executableLsofFileStore() -> RuntimeFileStoreSpy {
    let fileStore = RuntimeFileStoreSpy()
    fileStore.fileStates[Constants.Commands.lsof] = .executable
    return fileStore
}

private struct FreshInstallPreflightCommandRunner: RuntimeCommandRunner {
    let result: RuntimeProcessResult

    func run(_ executable: String, arguments: [String]) -> RuntimeProcessResult {
        result
    }

    func runWritingOutput(_ executable: String, arguments: [String], output: URL) -> RuntimeProcessResult {
        result
    }
}
